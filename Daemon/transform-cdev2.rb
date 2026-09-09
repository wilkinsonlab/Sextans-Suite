# frozen_string_literal: true

require 'sinatra'
require 'rest-client'
require './http_utils'
require 'open3'
require 'cgi'
require 'fileutils'

# This service is only ever called from other containers on the same internal
# compose network (by hostname, e.g. "cde-box-daemon:4567") or via its
# loopback-only published port -- never by a browser. Sinatra 4.x/
# rack-protection 4.x enable Rack::Protection::HostAuthorization by default,
# which rejects any Host header outside a small built-in allowlist.
#
# HostAuthorization defends against DNS-rebinding attacks, where a *browser*
# is tricked into sending a request with an attacker-chosen Host header.
# There is no browser in this call path -- any caller fully controls its own
# Host header regardless of what this check requires, so it provides no real
# protection here. Matches the same fix already applied to yarrrml-rdfizer's
# t.rb, kept consistent for the same reason: Sinatra's own config passthrough
# for this has proven unreliable across versions in this codebase's sibling
# projects (see neuromuscular-disease-ontology's nmdo-search memory notes),
# so monkeypatching accepts? directly is the fix that has actually held.
require 'rack/protection/host_authorization'
class Rack::Protection::HostAuthorization
  def accepts?(_request)
    true
  end
end

include HTTPUtils

get '/' do
  update
  caresm
  yarrrml_substitute
  execute
  load_cde
  cleanup
  metadata_update
  "Execution complete.  See docker log for errors (if any)\n\n"
end

LIVE_MAPPING = '/data/CARE_Fiab_yarrrml.yaml'
STAGED_MAPPING = '/data/.staged_CARE_Fiab_yarrrml.yaml'
# Baked into this image at build time (Daemon/smoketest/fixture.csv), never
# fetched over the network -- see smoke_test_passed? for why that matters.
SMOKETEST_FIXTURE_CSV = File.expand_path('smoketest/fixture.csv', __dir__)

def update
  warn 'first open3 git pull'
  o, e, _s = Open3.capture3('cd CARE-Semantic-Model-Version-2 && git pull')
  warn "second open3 copy yarrrml #{o}  #{e}"
  o, e, _s = Open3.capture3("cp -rf ./CARE-Semantic-Model-Version-2/implementation/YARRRML/CARE_Fiab_yarrrml.yaml #{STAGED_MAPPING}")
  warn "second open3 complete #{o} #{e}"

  if smoke_test_passed?(STAGED_MAPPING)
    warn 'smoke test passed -- promoting freshly-pulled CARE-SM-2 mapping to live'
    FileUtils.cp(STAGED_MAPPING, LIVE_MAPPING)
  elsif File.exist?(LIVE_MAPPING)
    warn 'SMOKE TEST FAILED -- a freshly-pulled CARE-SM-2 mapping failed validation ' \
         "against the known-good fixture. NOT promoting it; keeping the previous, " \
         'already-verified mapping live. Investigate the upstream ' \
         'CARE-Semantic-Model-Version-2 repository before this happens again.'
  else
    warn 'SMOKE TEST FAILED, and this is a first-ever run with no previous mapping to ' \
         'fall back to -- promoting the new mapping anyway since there is nothing better ' \
         'to use. Investigate the upstream CARE-Semantic-Model-Version-2 repository.'
    FileUtils.cp(STAGED_MAPPING, LIVE_MAPPING)
  end
end

# The one thing standing between "always auto-update to the latest CARE-SM-2
# mapping" and "blindly trust whatever the next git pull happens to fetch."
# Runs the *staged* (not-yet-promoted) mapping through the real mapping
# engine against a small, static, known-good fixture -- both the fixture CSV
# and the expected-output checks below are Sextans-Suite's own, reviewed and
# committed here, never fetched from CARE-Semantic-Model-Version-2 itself.
# That's deliberate: if the check's own notion of "correct" came from the
# same upstream being validated, a compromised upstream could corrupt both
# halves together and the check would mean nothing.
#
# Runs through yarrrml-rdfizer under its own dedicated "_smoketest" type
# (isolated tmp/triples per t.rb's per-type layout) so it can never collide
# with a real "CARE" run's own scratch files. Its output is never uploaded to
# Virtuoso -- this is a local file check only, discarded afterward.
def smoke_test_passed?(staged_mapping)
  warn 'starting CARE-SM-2 mapping smoke test'
  smoketest_mapping = '/data/_smoketest_yarrrml.yaml'
  substitute_baseuri(staged_mapping, smoketest_mapping)
  FileUtils.cp(SMOKETEST_FIXTURE_CSV, '/data/CARE.csv')
  RestClient.get('http://yarrrml-rdfizer:4567/_smoketest')

  output_file = '/data/_smoketest/triples/_smoketest.nq'
  passed = File.exist?(output_file) && smoke_test_output_valid?(File.read(output_file))
  warn "CARE-SM-2 mapping smoke test #{passed ? 'PASSED' : 'FAILED'}"
  passed
rescue StandardError => e
  warn "CARE-SM-2 mapping smoke test errored, treating as failed: #{e}"
  false
end

# Deliberately coarse, structural checks -- not trying to be a full RML
# correctness suite, just enough to catch "this mapping is broken or has been
# tampered with" before it ever touches real data. The known fixture (see
# Daemon/smoketest/fixture.csv) produces several dozen triples across two
# patients and includes a real xsd:boolean value.
def smoke_test_output_valid?(nquads_content)
  lines = nquads_content.lines.reject { |l| l.strip.empty? }
  return false if lines.length < 20

  nquads_content.include?('XMLSchema#boolean')
end

def caresm
  warn 'starting CareSM'

  warn 'calling the caresm interface'
  _res = RestClient.post('http://caresm:8000/toolkit', '{}')
  sleep 3
  warn _res.inspect
  # end
  # warn "finished Hefesto"
end

def yarrrml_substitute
  warn 'starting yarrrml substitution'
  substitute_baseuri(LIVE_MAPPING, '/data/CARE_yarrrml.yaml')
  warn 'finished yarrrml substitution'
end

def substitute_baseuri(src, dest)
  baseuri = ENV.fetch('baseURI', 'http://example.org/')
  baseuri = 'http://example.org/' if baseuri.empty?
  content = File.read(src)
  content.gsub!('|||baseURI|||', baseuri)
  File.write(dest, content)
end

# Custom datatypes: a user's own CSV + their own YARRRML mapping, for
# anything CARE-SM-2 doesn't model. Convention: /data/custom/<name>.csv +
# /data/custom/<name>_yarrrml.yaml (matching basenames), entirely
# user-authored -- see Fix-install/README.md. These never touch the Toolkit
# or the git-pulled CARE-SM-2 mapping at all; each one is a fully independent
# yarrrml-rdfizer run under its own "custom-<name>" type (isolated tmp/
# triples per t.rb), triggered here and merged into the same Virtuoso upload
# as the CARE-SM output. A CSV with no matching mapping (or vice versa) is
# skipped with a warning, not treated as fatal -- one bad custom entry
# shouldn't block the real CARE-SM transform.
def custom_type_names
  Dir['/data/custom/*.csv'].filter_map do |csv_path|
    name = File.basename(csv_path, '.csv')
    yarrrml_path = "/data/custom/#{name}_yarrrml.yaml"
    unless File.exist?(yarrrml_path)
      warn "custom datatype '#{name}': no matching #{yarrrml_path}, skipping"
      next
    end
    name
  end
end

def execute
  warn 'executing transform'
  purge_nt
  trigger_type('CARE') if File.exist?('/data/CARE.csv')
  custom_type_names.each { |name| trigger_type("custom-#{name}") }
  warn 'done transform'
end

def trigger_type(type)
  warn "triggering yarrrml-rdfizer for type '#{type}'"
  RestClient.get("http://yarrrml-rdfizer:4567/#{type}")
rescue StandardError => e
  warn "transform for type '#{type}' failed: #{e}"
end

def load_cde
  triples_dirs = ['/data/CARE/triples']
  custom_type_names.each { |name| triples_dirs << "/data/custom-#{name}/triples" }

  files = triples_dirs.flat_map { |d| Dir["#{d}/*.nq"] }
  concatenated = ''
  files.each do |f|
    warn "Processing file #{f}"
    content = File.read(f)
    concatenated += content
    warn "The length of the content to upload is now #{concatenated.length}"
  end
  File.write('/tmp/check.nq', concatenated)

  write_to_virtuoso(concatenated)
end

def write_to_virtuoso(concatenated)
  user = ENV.fetch('GraphDB_User', nil)
  pass = ENV.fetch('GraphDB_Pass', nil)
  network = ENV['networkname'] || 'virtuoso'

  clear_all_graphs(network, user, pass)

  # A graph URI (e.g. urn:{prefix}:sextans-fix), not a bare repository name --
  # Virtuoso is one-instance-one-database with no separate "repository" concept;
  # isolation between different prefix installs is via named graph instead.
  #
  # This ?graph= target is actually never consulted for n-quads content --
  # each quad carries its own embedded graph URI (CARE-SM's YARRRML mints a
  # fresh `this:$(uniqid)_Record` graph per patient record), and Virtuoso
  # routes each quad to that graph regardless of this parameter, same as any
  # conformant SPARQL 1.1 Graph Store Protocol implementation. Left in place
  # since the Graph Store Protocol's PUT still requires *a* target graph
  # parameter to be present in the request, and it's harmless as a no-op.
  graph = ENV.fetch('GRAPHDB_REPONAME')
  url = "http://#{network}:8890/sparql-graph-crud-auth?graph=#{CGI.escape(graph)}"

  # Virtuoso's Graph Store Protocol write endpoint requires real HTTP Digest auth
  # and rejects Basic auth outright (401, no retry) -- HTTPUtils.put (rest-client)
  # only ever sends Basic, so it can't authenticate here. See HTTPUtils.put_digest.
  response = HTTPUtils.put_digest(url, 'application/n-quads', concatenated, user, pass)
  warn "Virtuoso write response: #{response.code} #{response.message}"
  response
end

def clear_all_graphs(network, user, pass)
  # GraphDB's old write path (PUT /repositories/{repo}/statements, no
  # ?context=) replaced the *entire* repository's contents on every
  # transform -- a real snapshot, not an accumulation. Virtuoso's write path
  # above can't reproduce that the same way (each record lands in its own
  # freshly-minted graph, never the same URI twice), so without this, every
  # run's data would just pile up forever alongside every previous run's.
  #
  # SPARQL's own "CLEAR ALL" does NOT do this on Virtuoso -- confirmed live:
  # it reports success but leaves real data graphs untouched (only
  # Virtuoso's own reserved/system graphs seem to be in scope for "ALL").
  # Explicit "CLEAR GRAPH <uri>" does work, so: enumerate every graph whose
  # URI starts with the configured baseURI (CARE-SM's YARRRML mints all of
  # its per-record graphs under `this:`, i.e. baseURI -- never touches
  # Virtuoso's own internal graphs, which don't match that prefix) and clear
  # each one individually before writing fresh data.
  #
  # Scope limitation: this only clears graphs under baseURI. A custom
  # datatype's own YARRRML (see the custom/ pipeline) is free to mint graphs
  # under any URI it likes; if it wants this same replace-on-write behavior,
  # its graphs need to live under baseURI too -- otherwise they accumulate
  # like everything did before this fix.
  baseuri = ENV.fetch('baseURI', 'http://example.org/')
  baseuri = 'http://example.org/' if baseuri.empty?
  graphs = data_graphs_under(network, baseuri, user, pass)
  warn "Clearing #{graphs.length} existing data graph(s) under #{baseuri} before this write"
  graphs.each { |g| clear_graph(network, g, user, pass) }
end

def data_graphs_under(network, baseuri, user, pass)
  url = "http://#{network}:8890/sparql-auth"
  query = 'SELECT DISTINCT ?g WHERE { GRAPH ?g {?s ?p ?o} ' \
          "FILTER(STRSTARTS(STR(?g), #{sparql_string_literal(baseuri)})) }"
  body = "query=#{CGI.escape(query)}"
  response = HTTPUtils.post_digest(url, 'application/x-www-form-urlencoded', body, user, pass)
  # Parsed directly out of Virtuoso's default SPARQL-results XML rather than
  # pulling in a full XML parser for one field -- the response shape here is
  # simple and stable enough that a plain regex is the pragmatic choice.
  response.body.scan(%r{<binding name="g"><uri>(.*?)</uri></binding>}).flatten
end

def clear_graph(network, graph_uri, user, pass)
  url = "http://#{network}:8890/sparql-auth"
  body = "update=#{CGI.escape("CLEAR GRAPH #{sparql_iri_literal(graph_uri)}")}"
  response = HTTPUtils.post_digest(url, 'application/x-www-form-urlencoded', body, user, pass)
  warn "Cleared graph #{graph_uri}: #{response.code} #{response.message}"
  response
end

def sparql_string_literal(str)
  "\"#{str.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}\""
end

def sparql_iri_literal(uri)
  "<#{uri.gsub('>', '%3E')}>"
end

def purge_nt
  File.delete('/data/triples/*.nt')
rescue StandardError
  warn 'Deleting the exisiting .nt files failed!'
ensure
  warn 'looks like it is already clean in here!'
end

def metadata_update # rubocop:disable Metrics/AbcSize
  return if ENV['DIST_RECORDID'].nil? || ENV['DATASET_RECORDID'].nil? || ENV['DATA_SPARQL_ENDPOINT'].nil?
  return if ENV['DIST_RECORDID'].empty? || ENV['DATASET_RECORDID'].empty? || ENV['DATA_SPARQL_ENDPOINT'].empty?

  warn 'calling metadata updater image'
  begin
    resp = RestClient.get('http://updater:4567/update')
  rescue StandardError
    warn "\n\n\ncall to http://updater:4567/update FAILED"
    warn resp
  end
  warn "\n\nMetadata Update complete - look above for errors\n\n"
end

def cleanup
  warn 'closing cleanup open3'
  _o, _s = Open3.capture2('rm -rf /data/triplesstats.csv')
end
