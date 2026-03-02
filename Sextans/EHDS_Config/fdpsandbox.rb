require 'rest-client'
require 'json'
require './fdp_client'
require './fdp_schema'
require './fdp_resource'

base_url = 'http://localhost:9000'
email    = 'albert.einstein@example.com' # change this
password = 'password' # change this

fdp = FDP::Client.new(base_url: base_url, email: email, password: password)

uuids = fdp.list_current_schemas
puts "\nStarting Schemas:"
uuids.each do |name, definition|
  puts "#{name}: #{definition['uuid']}"
end

# create a usable new schema
#
# definition_file = './Schema/biobank.shacl'
# definition = File.read(definition_file).strip
# schema = FDP::Schema.new(
#   name: 'Biobank', # the key to the UUID hash
#   label: 'Biobank',
#   description: 'Custom SHACL shape for biobanks, extending the generic Resource',
#   prefix: 'biobank', # optional, for auto-generating resource URLs
#   definition: definition,
#   version: '3.0.0',
#   parents: [uuids['Resource']['uuid']], # inherit from the generic Resource shape,
#   targetclasses: ['https://w3id.org/ejp-rd/vocabulary#Biobank'] # optional, for UI display and validation targeting
# )
#
# schema.write_to_fdp(client: fdp)
#
# uuids = fdp.list_current_schemas
# puts "\nFinal Schemas:"
# uuids.each do |name, definition|
#   puts "#{name}: #{definition['uuid']}"
# end

# OVERWRITE an existing schema with a new definition (same name, different content)
schemaobjs = fdp.retrieve_current_schemas
puts "\nSchemas:"
schemaobjs.each do |schema|
  puts "schema name: #{schema.name}, uuid: #{schema.uuid}, version: #{schema.version}"
  # puts "definition: #{schema.definition[0..30]}..."
end

definition_file = './Schema/resource.shacl'
definition = File.read(definition_file).strip
resourceschema = schemaobjs.find { |s| s.name == 'Resource' }
puts "\nOriginal Resource schema definition:\n#{resourceschema.definition}\n\n"
resourceschema.definition = definition
# DO NOT MODIFY VERSION - this is incremented automatically in the overwrite_schema_in_fdp method to ensure the API accepts it as a new draft version, otherwise it will reject it as a duplicate of the existing published version. The version in the object is updated for clarity, but the API actually ignores it and just increments the existing version by 1.
resourceschema.write_to_fdp(client: fdp) # should trigger an overwrite since the name is the same and UUID is included in payload

schemaobjs = fdp.retrieve_current_schemas
puts "\nSchemas:"
schemaobjs.each do |schema|
  puts "schema name: #{schema.name}, uuid: #{schema.uuid}"
  puts "definition: #{schema.definition}" if schema.name == 'Resource'
end

abort

# uuids = fdp.retrieve_current_schemas
# puts "\nSchemas:"
# uuids.each do |schema|
#   puts "schema name: #{schema.name}, uuid: #{schema.uuid}, definition: #{schema.definition[0..30]}..."
# end
# puts "\nSchemas To Payload:"
# uuids.each do |schema|
#   puts "schema name: #{schema.name}, payload: #{JSON.pretty_generate(schema.to_api_payload)}"
# end

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
