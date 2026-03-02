require 'rest-client'
require 'json'
require './fdp_client'
require './fdp_schema'
require './fdp_resource'

base_url = 'http://localhost:9000'
email    = 'albert.einstein@example.com' # change this
password = 'password' # change this

fdp = FDP::Client.new(base_url: base_url, email: email, password: password)

uuids = fdp.retrieve_current_schemas
puts "\nSchemas:"
# uuids.each do |schema|
#   puts "schema name: #{schema.name}, uuid: #{schema.uuid}, definition: #{schema.definition[0..30]}..."
# end
puts "\nSchemas To Payload:"
uuids.each do |schema|
  next unless ['Biobank Test', 'Biobank'].include? schema.name

  puts "schema name: #{schema.name}, payload: #{JSON.pretty_generate(schema.to_api_payload)}\n\n"
  puts "\n\n\n#{schema.definition}"
end

abort

resources = fdp.list_current_resources
puts "\nResources:"
resources.each do |name, definition|
  puts "#{name}: #{definition['uuid']}"
end

# resources = fdp.retrieve_current_resources
# puts "\nResources:"
# resources.each do |resource|
#   puts "resource name: #{resource.name}, uuid: #{resource.uuid}, prefix: #{resource.prefix}, schemas: #{resource.schemas.join(', ')}"
# end

# puts "\nResource To Payload:"
# resources.each do |resource|
#   puts "resource name: #{resource.name}, payload: #{JSON.pretty_generate(resource.to_api_payload)}"
#   break
# end

# WRITE RESOURCE
resource = FDP::Resource.new(
  resourcejson: {
    name: 'ERDERA BioBank',
    urlPrefix: 'biobank',
    metadataSchemaUuids: [uuids['Biobank']['uuid']], # UUID of the Biobank1 schema we just created
    targetClassUris: ['https://w3id.org/ejp-rd/vocabulary#Biobank'], # RDF class this resource represents
    children: [
      {
        resourceDefinitionUuid: uuids['Resource']['uuid'], # link to the generic Resource definition
        relationUri: 'http://example.org/ontology/hasPart', # how this child resource relates to the parent
        listView: {
          title: 'Samples in Biobank1',
          tagsUri: nil,
          metadata: []
        }
      }
    ],
    externalLinks: [
      { label: 'Biobank1 Website', url: 'http://biobank1.example.com' }
    ]
  }
)
resource.write_to_fdp(client: fdp)
