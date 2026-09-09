# frozen_string_literal: true

require 'sinatra'
require 'rest-client'
require './http_utils'
require 'open3'
require 'cgi'

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

def update
  warn 'first open3 git pull'
  o, e, _s = Open3.capture3('cd CARE-Semantic-Model-Version-2 && git pull')
  warn "second open3 copy yarrrml #{o}  #{e}"
  o, e, _s = Open3.capture3('cp -rf ./CARE-Semantic-Model-Version-2/implementation/YARRRML/CARE_Fiab_yarrrml.yaml  /data') # CARE-SM-2
  warn "second open3 complete #{o} #{e}"
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
  baseuri = ENV.fetch('baseURI', 'http://example.org/')
  baseuri = 'http://example.org/' if baseuri.empty?
  # template_list = Dir['/conf/CSV_yarrrml_template.yaml']
  # template_list.each do |t|  # now it is always /conf/CSV_yarrrml_template.yaml... but maybe one day we will be more flexible?
  content = File.read('/data/CARE_Fiab_yarrrml.yaml')
  content.gsub!('|||baseURI|||', baseuri)
  f = File.open('/data/CARE_yarrrml.yaml', 'w')
  f.puts content
  f.close
  # end
  warn 'finished yarrrml substitution'
end

def execute
  warn 'executing transform'
  purge_nt
  datatype_list = Dir['/data/CARE.csv']
  datatype_list.each do |d|
    datatype = d.match(%r{.+/([^.]+)\.csv})[1] # this is totally useless now... but we'll keep it just for posterity!
    next unless datatype

    _resp = RestClient.get("http://yarrrml-rdfizer:4567/#{datatype}")
  end
  warn 'done transform'
end

def load_cde
  files = Dir['/data/triples/*.nq']
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
  # A graph URI (e.g. urn:{prefix}:sextans-fix), not a bare repository name --
  # Virtuoso is one-instance-one-database with no separate "repository" concept;
  # isolation between different prefix installs is via named graph instead.
  graph = ENV.fetch('GRAPHDB_REPONAME')
  url = "http://#{network}:8890/sparql-graph-crud-auth?graph=#{CGI.escape(graph)}"

  # Virtuoso's Graph Store Protocol write endpoint requires real HTTP Digest auth
  # and rejects Basic auth outright (401, no retry) -- HTTPUtils.put (rest-client)
  # only ever sends Basic, so it can't authenticate here. See HTTPUtils.put_digest.
  response = HTTPUtils.put_digest(url, 'application/n-quads', concatenated, user, pass)
  warn "Virtuoso write response: #{response.code} #{response.message}"
  response
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
