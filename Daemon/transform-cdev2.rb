# frozen_string_literal: true

require 'sinatra'
require 'rest-client'
require './http_utils'
require 'open3'
require 'cgi'
require 'fileutils'
require 'yaml'
require 'rdf'
require 'rdf/nquads'

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
  model = data_model
  update_mappings(model)
  run_toolkit(model)
  yarrrml_substitute if model['mapping_source']['kind'] == 'baked'
  types = types_to_run(model)
  # Fail closed: each run replaces the previous snapshot, so proceeding without
  # a type's mapping would silently wipe that type from the store. Stop now,
  # before anything is cleared or uploaded.
  missing = types.reject { |t| File.exist?(mapping_path(t)) }
  unless missing.empty?
    warn "ABORTING: no mapping available for #{missing.join(', ')}; nothing was cleared or uploaded"
    halt 500, "Aborted: no mapping available for #{missing.join(', ')}. See docker log.\n"
  end
  execute(types)
  begin
    load_cde(types)
  rescue InvalidDataError => e
    warn "ABORTING: #{e.message}"
    halt 422, "Aborted: #{e.message}\n"
  end
  cleanup
  metadata_update
  "Execution complete.  See docker log for errors (if any)\n\n"
end

# Which data model this install transforms into is chosen at install time
# (DATA_MODEL, written to .env by the Fix installer) and defined by a small
# file in models/. Unset/empty means CARE-SM-2, which is what every install
# before this setting existed was doing.
MODELS_DIR = File.expand_path('models', __dir__)
DEFAULT_DATA_MODEL = 'CARE-SM-2'
# Where mapping repositories for non-baked models are checked out at runtime.
MODEL_SRC_DIR = File.expand_path('model-src', __dir__)

def data_model
  name = ENV['DATA_MODEL'].to_s.strip
  name = DEFAULT_DATA_MODEL if name.empty?
  # The name becomes part of a file path -- whitelist it.
  raise ArgumentError, "invalid DATA_MODEL '#{name}'" unless name =~ /\A[a-zA-Z0-9_-]+\z/

  file = File.join(MODELS_DIR, "#{name.downcase}.yml")
  raise ArgumentError, "unknown DATA_MODEL '#{name}' (no #{file})" unless File.exist?(file)

  YAML.safe_load_file(file).merge('key' => name.downcase)
end

# The types transformed on this run: only those whose source CSV is actually
# present. A type with no CSV is *not published* -- and, since each run replaces
# the previous snapshot, is not left behind from an earlier run either (this
# is how a data owner opts a type out, e.g. sensitive collection locations).
def types_to_run(model)
  types = Array(model['types']).select { |t| File.exist?("/data/#{t}.csv") }
  types.concat(custom_type_names.map { |name| "custom-#{name}" })
  types
end

# Where yarrrml-rdfizer (t.rb) looks for a type's mapping.
def mapping_path(type)
  return "/data/custom/#{type.delete_prefix('custom-')}_yarrrml.yaml" if type.start_with?('custom-')

  "/data/#{type}_yarrrml.yaml"
end

# How a model's mappings are kept current depends on where they live:
#   baked -- CARE-SM-2 (cloned into the image at build time; git-pulled and
#            smoke-tested before use, see `update`)
#   git   -- a repository checked out at runtime (see update_git_mappings)
def update_mappings(model)
  case model['mapping_source']['kind']
  when 'baked' then update
  when 'git' then update_git_mappings(model)
  else raise ArgumentError, "model #{model['label']}: unknown mapping_source kind"
  end
end

# Git-sourced models (e.g. FLAIR-GG): keep a sparse checkout of the model's own
# mapping repository, and (re)generate /data/<type>_yarrrml.yaml from its
# <type>_yarrrml.pre-yaml files, with the |||baseURI||| placeholder filled in.
# NOTE: unlike CARE-SM-2 there is no fixture-based smoke test for these yet.
# The only check is a coarse one (non-empty, looks like YARRRML). Deliberately
# NOT a strict YAML parse: yarrrml-parser (JavaScript) accepts plain scalars
# such as `fao: https://...owl#CO_020:` that Ruby's stricter parser rejects,
# and FLAIR-GG's own mappings contain exactly that -- a Ruby-side parse here
# would wrongly refuse mappings the real engine runs fine.
def update_git_mappings(model)
  src = model.fetch('mapping_source')
  repo_dir = File.join(MODEL_SRC_DIR, model['key'])
  sync_model_repo(src, repo_dir)

  base_uri = ENV.fetch('baseURI', 'http://example.org/')
  base_uri = 'http://example.org/' if base_uri.empty?

  Array(model['types']).each do |type|
    pre = File.join(repo_dir, src['path'], "#{type}#{src['suffix']}")
    unless File.exist?(pre)
      warn "model #{model['label']}: no mapping #{pre} for type '#{type}', skipping"
      next
    end
    content = File.read(pre).gsub('|||baseURI|||', base_uri)
    unless content =~ /^mappings?:/
      warn "model #{model['label']}: #{pre} does not look like a YARRRML mapping; " \
           'NOT promoting it, keeping the previous mapping (if any)'
      next
    end
    File.write("/data/#{type}_yarrrml.yaml", content)
    warn "model #{model['label']}: wrote /data/#{type}_yarrrml.yaml"
  end
end

def sync_model_repo(src, repo_dir)
  if File.directory?(File.join(repo_dir, '.git'))
    out, status = Open3.capture2e('git', '-C', repo_dir, 'pull', '--ff-only')
  else
    FileUtils.mkdir_p(File.dirname(repo_dir))
    out, status = Open3.capture2e('git', 'clone', '--depth', '1', '--filter=blob:none', '--sparse',
                                  src.fetch('git'), repo_dir)
    if status.success?
      out2, status = Open3.capture2e('git', '-C', repo_dir, 'sparse-checkout', 'set', src.fetch('path'))
      out += out2
    end
  end
  warn "model repository sync #{status.success? ? 'ok' : 'FAILED (using whatever is already checked out)'}: #{out}"
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

# Every model is checked for a toolkit -- an optional service that sanity-checks
# and prepares the user's source data before it is mapped (CARE-SM-2's is the
# `caresm` Toolkit). A model that defines none is fine: note it and move on.
# A toolkit that IS defined but fails aborts the whole run here, before
# anything is cleared or uploaded, rather than mapping data it didn't approve.
def run_toolkit(model)
  toolkit = model['toolkit']
  if toolkit.nil? || toolkit['url'].to_s.empty?
    warn "model #{model['label']} defines no toolkit -- skipping the sanity check, moving on"
    return
  end

  warn "calling the #{model['label']} toolkit at #{toolkit['url']}"
  res = RestClient.post(toolkit['url'], '{}')
  sleep 3
  warn res.inspect
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

def execute(types)
  warn 'executing transform'
  purge_nt
  types.each { |type| trigger_type(type) }
  warn 'done transform'
end

def trigger_type(type)
  warn "triggering yarrrml-rdfizer for type '#{type}'"
  RestClient.get("http://yarrrml-rdfizer:4567/#{type}")
rescue StandardError => e
  warn "transform for type '#{type}' failed: #{e}"
end

def load_cde(types)
  # t.rb writes each type's output to /data/<type>/triples/ (custom types are
  # already "custom-<name>", so the same rule covers them).
  files = types.flat_map { |type| Dir["/data/#{type}/triples/*.nq"] }
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
  # Legacy names (GraphDB_User/GraphDB_Pass/GRAPHDB_REPONAME) are still honoured so
  # a Sextans Fix install created before the rename keeps working when only this
  # image is updated -- its compose file and .env still use the old names.
  user = ENV['TRIPLESTORE_USER'] || ENV.fetch('GraphDB_User', nil)
  pass = ENV['TRIPLESTORE_PASS'] || ENV.fetch('GraphDB_Pass', nil)
  network = ENV['networkname'] || 'virtuoso'

  # Before anything is cleared: if the content can't be parsed, fail here with
  # the existing data untouched.
  concatenated = assign_default_graph(concatenated, triplestore_graph)

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
  # (Triples that carry no graph at all were given TRIPLESTORE_GRAPH above,
  # precisely because this parameter would NOT have caught them.)
  graph = triplestore_graph
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

  # The operator-chosen default graph (TRIPLESTORE_GRAPH, e.g. urn:<prefix>-sextans-fix)
  # is where any triple whose mapping names no graph of its own ends up (see
  # write_to_virtuoso) -- which is every triple for a model like FLAIR-GG, whose
  # mappings mint no named graphs. That graph is not under baseURI, so the
  # sweep above never sees it; clear it explicitly so those runs replace the
  # previous snapshot too instead of accumulating. It is a graph dedicated to
  # this install (the installer names it after your prefix); don't point
  # TRIPLESTORE_GRAPH at a graph that holds anything else.
  default_graph = triplestore_graph
  if protected_graph?(default_graph)
    warn "NOT clearing TRIPLESTORE_GRAPH #{default_graph}: it looks like a vocabulary/system graph"
  else
    warn "Clearing default graph #{default_graph} before this write"
    clear_graph(network, default_graph, user, pass)
  end
end

def triplestore_graph
  ENV['TRIPLESTORE_GRAPH'] || ENV.fetch('GRAPHDB_REPONAME')
end

# A triple with no graph of its own -- every triple for a mapping that mints no
# named graphs (FLAIR-GG), and a few from CARE-SM-2's -- is *not* put in the
# request's ?graph= target by Virtuoso: for n-quads content it lands in a
# built-in placeholder graph (urn:dummy), which nothing ever clears, so those
# triples used to accumulate across runs. Give them an explicit home instead:
# the operator-chosen TRIPLESTORE_GRAPH, which write_to_virtuoso then also
# clears on every run (see clear_all_graphs).
def assign_default_graph(nquads, graph_uri)
  default_graph = RDF::URI(graph_uri)
  invalid = []
  out = RDF::NQuads::Writer.buffer(validate: false) do |writer|
    RDF::NQuads::Reader.new(nquads, validate: false).each_statement do |st|
      invalid << st unless st.valid?
      st = RDF::Statement.new(st.subject, st.predicate, st.object, graph_name: default_graph) if st.graph_name.nil?
      writer << st
    end
  end
  raise InvalidDataError, invalid_data_message(invalid) unless invalid.empty?

  out
end

# Refuse to publish data that isn't valid RDF -- e.g. "2024/01/01" typed
# xsd:date (which needs 2024-01-01). Better a clear failure now, with the
# existing data left untouched, than bad values silently published; the fix
# belongs in the data export.
class InvalidDataError < StandardError; end

def invalid_data_message(invalid)
  shown = invalid.first(10).map { |st| "  #{st.subject.to_ntriples} #{st.predicate.to_ntriples} #{st.object.to_ntriples}" }
  "#{invalid.length} statement(s) produced from your data are not valid RDF, so NOTHING was " \
    "cleared or uploaded. Fix your data export and try again. Typical causes: dates not in ISO " \
    "8601 form (YYYY-MM-DD, not YYYY/MM/DD), non-numeric text in a numeric column, or malformed " \
    "URIs. First #{shown.length}:\n#{shown.join("\n")}"
end

# Never wipe Virtuoso's own graphs or well-known vocabularies if
# TRIPLESTORE_GRAPH is ever mis-set to one of them.
def protected_graph?(uri)
  uri.start_with?('http://www.openlinksw.com/', 'http://www.w3.org/', 'http://localhost')
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
  body = "update=#{CGI.escape("CLEAR SILENT GRAPH #{sparql_iri_literal(graph_uri)}")}"
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
