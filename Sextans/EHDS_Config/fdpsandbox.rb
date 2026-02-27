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
puts "\nSchemas:"
uuids.each do |name, definition|
  puts "#{name}: #{definition['uuid']}"
end

uuids = fdp.retrieve_current_schemas
puts "\nSchemas:"
uuids.each do |schema|
  puts "schema name: #{schema.name}, uuid: #{schema.uuid}, definition: #{schema.definition[0..30]}..."
end
puts "\nSchemas To Payload:"
uuids.each do |schema|
  puts "schema name: #{schema.name}, payload: #{JSON.pretty_generate(schema.to_api_payload)}"
  break
end

resources = fdp.list_current_resources
puts "\nResources:"
resources.each do |name, definition|
  puts "#{name}: #{definition['uuid']}"
end

resources = fdp.retrieve_current_resources
puts "\nResources:"
resources.each do |resource|
  puts "resource name: #{resource.name}, uuid: #{resource.uuid}, prefix: #{resource.prefix}, schemas: #{resource.schemas.join(', ')}"
end

puts "\nResource To Payload:"
resources.each do |resource|
  puts "resource name: #{resource.name}, payload: #{JSON.pretty_generate(resource.to_api_payload)}"
  break
end

#   WRITING SCHEMAS
# definition_file = './samples/biobank.shacl'
# definition = File.read(definition_file).strip

# schema = FDP::Schema.new(
#   name: 'Biobank1',
#   label: 'Biobank1 Shape',
#   description: 'Custom SHACL shape for biobanks, extending the generic Resource',
#   prefix: 'biobank1', # optional, for auto-generating resource URLs
#   definition: definition,
#   parents: [uuids['Resource']['uuid']] # inherit from the generic Resource shape
# )

# fdp.write_schema(schema: schema)
