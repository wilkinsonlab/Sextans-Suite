require 'rest-client'
require 'json'
require '../fdp_client'
require '../fdp_schema'
require '../fdp_resource'

base_url = 'http://localhost:9000'
email    = 'albert.einstein@example.com' # change this
password = 'password' # change this
schema_base = './Schemas'

fdp = FDP::Client.new(base_url: base_url, email: email, password: password)

# create a quick lookup for schema uuids by name
uuids = fdp.list_current_schemas
puts "\nStarting Schemas:"
uuids.each do |name, definition|
  puts "#{name}: #{definition['uuid']}"
end

resources = fdp.retrieve_current_resources
puts "\nResource To Payload:"
resources.each do |resource|
  puts "resource name: #{resource.name} uuid: #{resource.uuid}"
end

schemaobjs = fdp.retrieve_current_schemas
puts "\nSchemas:"
schemaobjs.each do |schema|
  puts "schema name: #{schema.name}, uuid: #{schema.uuid}, version: #{schema.version}"
  # puts "definition: #{schema.definition}..."
end

# 1 Overwrite Resource Schema with new definition
schemaobjs.each do |schema|
  next unless schema.name == 'Resource'

  schema.name = 'Resource'
  schema.description = 'A generic resource schema definition for ERDERA, based on the generic Resource shape but with added constraints and properties specific to ERDERA use cases'
  schema.prefix = 'resource'
  schema.label = 'ERDERA Resource'
  schema.definition = File.read("#{schema_base}/resource.shacl")
  warn "trying to overwrite existing schea with new name: #{schema.name} and same UUID: #{schema.uuid}"
  schema.write_to_fdp(client: fdp)
end

# 2 Overwrite DataService Schema with new
schemaobjs.each do |schema|
  next unless schema.name == 'Data Service'

  schema.name = 'Data Service'
  schema.description = 'A data service schema definition for ERDERA, based on the generic Data Service shape but with added constraints and properties specific to ERDERA use cases'
  schema.prefix = 'dataservice'
  schema.label = 'ERDERA Data Service'
  schema.definition = File.read("#{schema_base}/data-service.shacl")
  warn "trying to overwrite existing schema with new name: #{schema.name} and same UUID: #{schema.uuid}"
  schema.write_to_fdp(client: fdp)
end

# 3 Overwrite Dataset Schema with new
schemaobjs.each do |schema|
  next unless schema.name == 'Dataset'

  schema.name = 'Dataset'
  schema.description = 'A dataset schema definition for ERDERA, based on the generic Dataset shape but with added constraints and properties specific to ERDERA use cases'
  schema.prefix = 'dataset'
  schema.label = 'ERDERA Dataset'
  warn "trying to overwrite existing schema with new name: #{schema.name} and same UUID: #{schema.uuid}"
  schema.write_to_fdp(client: fdp)
end

uuids = fdp.list_current_schemas
resources = fdp.retrieve_current_resources
schemaobjs = fdp.retrieve_current_schemas

# 4 Create a Biobank Schema
biobank = FDP::Schema.new(client: fdp,
                          # targetclasses:, parents: [],
                          # children: [], uuid: nil, abstractschema: false)
                          name: 'Biobank',
                          description: 'A biobank schema definition for ERDERA',
                          version: '1.0.0', # must be major.minor.patch and must be incremented for each update
                          definition: File.read("#{schema_base}/biobank.shacl"),
                          prefix: 'biobank',
                          label: 'Biobank',
                          targetclasses: ['https://w3id.org/ejp-rd/vocabulary#Biobank'],
                          parents: [uuids['Resource']['uuid']], # inherit from the generic Resource shape
                          abstractschema: false)

puts "\nBiobank Schema Payload:"
puts JSON.pretty_generate(biobank.to_api_payload)

biobank.write_to_fdp(client: fdp)
# refresh
uuids = fdp.list_current_schemas
resources = fdp.retrieve_current_resources

# 5 Create a Registry Schena
#
registry = FDP::Schema.new(client: fdp,
                           # targetclasses:, parents: [],
                           # children: [], uuid: nil, abstractschema: false)
                           name: 'Patient Registry',
                           description: 'A patient registry schema definition for ERDERA',
                           version: '1.0.0', # must be major.minor.patch and must be incremented for each update
                           definition: File.read("#{schema_base}/patient-registry.shacl"),
                           prefix: 'patientregistry',
                           label: 'Patient Registry',
                           targetclasses: ['https://w3id.org/ejp-rd/vocabulary#PatientRegistry'],
                           parents: [uuids['Resource']['uuid']], # inherit from the generic Resource shape
                           abstractschema: false)

puts "\Registry Schema Payload:"
puts JSON.pretty_generate(registry.to_api_payload)

registry.write_to_fdp(client: fdp)
# refresh
uuids = fdp.list_current_schemas
resources = fdp.retrieve_current_resources

# 6 Create a Guideline Schena
#
guideline = FDP::Schema.new(client: fdp,
                            # targetclasses:, parents: [],
                            # children: [], uuid: nil, abstractschema: false)
                            name: 'Guideline',
                            description: 'A guideline schema definition for ERDERA',
                            version: '1.0.0', # must be major.minor.patch and must be incremented for each update
                            definition: File.read("#{schema_base}/guideline.shacl"),
                            prefix: 'guideline',
                            label: 'Guideline',
                            targetclasses: ['https://w3id.org/ejp-rd/vocabulary#Guideline'],
                            parents: [uuids['Resource']['uuid']], # inherit from the generic Resource shape
                            abstractschema: false)

puts "\Guideline Schema Payload:"
puts JSON.pretty_generate(guideline.to_api_payload)

guideline.write_to_fdp(client: fdp)
# refresh
uuids = fdp.list_current_schemas
resources = fdp.retrieve_current_resources
schemaobjs = fdp.retrieve_current_schemas

###############################################   SCHEMAS DONE  ##############################################################

# 7  Create a Patient Registry Resource

# Resource Includes :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links
# Child:  :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
# External Link:  :url, :label, :description
resource = FDP::Resource.new(client: fdp,
                             name: 'ERDERA Patient Registry',
                             description: 'A patient registry resource for ERDERA FDPs, conforming to the Patient Registry schema',
                             prefix: 'patientregistry',
                             schemas: [uuids['Patient Registry']['uuid']],
                             targeturis: ['https://w3id.org/ejp-rd/vocabulary#PatientRegistry'])

puts "\nPatient Registry Resource Payload:"
puts JSON.pretty_generate(resource.to_api_payload)

resource.write_to_fdp(client: fdp)

abort

# 8  Create a Biobank Resource
# Resource Includes :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links
# Child:  :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
# External Link:  :url, :label, :description
resource = FDP::Resource.new(client: fdp,
                             name: 'ERDERA Biobank',
                             description: 'A Biobank resource definition for ERDERA FDPs, conforming to the Biobank schema',
                             prefix: 'biobank',
                             schemas: [uuids['Biobank']['uuid']],
                             targeturis: ['https://w3id.org/ejp-rd/vocabulary#Biobank'])

puts "\nPatient Biobank Payload:"
puts JSON.pretty_generate(resource.to_api_payload)

resource.write_to_fdp(client: fdp)

# 9  Create a Guideline Resource
# Resource Includes :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links
# Child:  :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
# External Link:  :url, :label, :description
resource = FDP::Resource.new(client: fdp,
                             name: 'ERDERA Guideline',
                             description: 'A Guideline resource definition for ERDERA FDPs, conforming to the Guideline schema',
                             prefix: 'guideline',
                             schemas: [uuids['Guideline']['uuid']],
                             targeturis: ['https://w3id.org/ejp-rd/vocabulary#Guideline'])

puts "\nPatient Guideline Payload:"
puts JSON.pretty_generate(resource.to_api_payload)

resource.write_to_fdp(client: fdp)

# 10  Create the first DataService Resource
# Resource Includes :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links
# Child:  :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
# External Link:  :url, :label, :description
resource = FDP::Resource.new(client: fdp,
                             name: 'ERDERA Top Level Data Service',
                             description: 'A top level data service resource definition for ERDERA FDPs. This is used for services that provide analytics, but not serving e.g. registry or biobank dasta',
                             prefix: 'dataservice1',
                             schemas: [uuids['Data Service']['uuid']],
                             targeturis: ['https://w3id.org/ejp-rd/vocabulary#DataService'],
                             external_links: [FDP::ResourceExternalLink.new(
                               propertyuri: 'http://www.w3.org/ns/dcat#endpointURL',
                               title: 'endpointURL'
                             ), FDP::ResourceExternalLink.new(
                               propertyuri: 'http://www.w3.org/ns/dcat#endpointDescription',
                               title: 'endpointDescription'
                             ), FDP::ResourceExternalLink.new(
                               propertyuri: 'http://www.w3.org/ns/dcat#landingPage',
                               title: 'landingPage'
                             )])

puts "\nTop Level Data Service Payload:"
puts JSON.pretty_generate(resource.to_api_payload)

resource.write_to_fdp(client: fdp)

# 10  Create the second DataService Resource
# Resource Includes :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links
# Child:  :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
# External Link:  :title, :propertyuri
resource = FDP::Resource.new(client: fdp,
                             name: 'ERDERA Dataset Data Service',
                             description: 'A data service resource definition for ERDERA FDPs. This is used for services that serve datasets, e.g. registry or biobank data',
                             prefix: 'dataservice2',
                             schemas: [uuids['Data Service']['uuid']],
                             targeturis: ['https://w3id.org/ejp-rd/vocabulary#DataService'],
                             external_links: [FDP::ResourceExternalLink.new(
                               propertyuri: 'http://www.w3.org/ns/dcat#endpointURL',
                               title: 'endpointURL'
                             ), FDP::ResourceExternalLink.new(
                               propertyuri: 'http://www.w3.org/ns/dcat#endpointDescription',
                               title: 'endpointDescription'
                             ), FDP::ResourceExternalLink.new(
                               propertyuri: 'http://www.w3.org/ns/dcat#landingPage',
                               title: 'landingPage'
                             )])

puts "\nDataset Data Service Payload:"
puts JSON.pretty_generate(resource.to_api_payload)

resource.write_to_fdp(client: fdp)

# refresh
uuids = fdp.list_current_schemas
resources = fdp.retrieve_current_resources
schemaobjs = fdp.retrieve_current_schemas

puts resources
resources.each do |r|
  puts r.name
end
abort

#   Making Connections....

# Catalog has four children
catalog = resources.find { |r| r.name == 'Catalog' }
# add the three new children - Biobank, Registry, and Guideline
# :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
catalog.children <<
  FDP::ResourceChild.new(
    resourceDefinitionUuid: resources.find { |r| r.name == 'ERDERA Biobank' }.uuid,
    relationUri: 'http://purl.org/dc/terms/hasPart',
    listViewTitle: 'ERDERA Biobanks',
    listViewTagsUri: 'http://www.w3.org/ns/dcat#theme'
  )
catalog.children <<
  FDP::ResourceChild.new(
    resourceDefinitionUuid: resources.find { |r| r.name == 'ERDERA Guideline' }.uuid,
    relationUri: 'http://purl.org/dc/terms/hasPart',
    listViewTitle: 'ERDERA Guidelines',
    listViewTagsUri: 'http://www.w3.org/ns/dcat#theme'
  )
catalog.children <<
  FDP::ResourceChild.new(
    resourceDefinitionUuid: resources.find { |r| r.name == 'ERDERA Patient Registries' }.uuid,
    relationUri: 'http://purl.org/dc/terms/hasPart',
    listViewTitle: 'ERDERA Patient Registries',
    listViewTagsUri: 'http://www.w3.org/ns/dcat#theme'
  )
catalog.children <<
  FDP::ResourceChild.new(
    resourceDefinitionUuid: resources.find { |r| r.name == 'ERDERA Top Level Data Service' }.uuid,
    relationUri: 'http://www.w3.org/ns/dcat#service', #  ATTENTION!!  THIS IS DEFINED BY DCAT3
    listViewTitle: 'Top Level Data Services',
    listViewTagsUri: 'http://www.w3.org/ns/dcat#theme'
  )

puts "\New Catalog Resource Payload:"
puts JSON.pretty_generate(catalog.to_api_payload)

catalog.write_to_fdp(client: fdp)

# Distribution has a DataService
distribution = resources.find { |r| r.name == 'Distribution' }
# add the new child - ERDERA Dataset Data Service
# :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
distribution.children <<
  FDP::ResourceChild.new(
    resourceDefinitionUuid: resources.find { |r| r.name == 'ERDERA Dataset Data Service' }.uuid,
    relationUri: 'http://www.w3.org/ns/dcat#accessService', #  ATTENTION!!  THIS IS DEFINED BY DCAT3, and is DIFFErenT from above!!
    listViewTitle: 'Data Access Services',
    listViewTagsUri: 'http://www.w3.org/ns/dcat#theme'
  )

puts "\New Distribution Resource Payload:"
puts JSON.pretty_generate(distribution.to_api_payload)

distribution.write_to_fdp(client: fdp)

# Break the connection between FDP and DataService
# I will do this by causing it to inherit only FDP and Metadata Service schemas
fdp = resources.find { |r| r.name == 'FAIR Data Point' }
# add the new child - ERDERA Dataset Data Service
# :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata
fdp.schemas = [
  resources.find { |r| r.name == 'Metadata Service' }.uuid,
  resources.find { |r| r.name == 'FAIR Data Point' }.uuid
]

puts "\nNew FDP Payload:"
puts JSON.pretty_generate(fdp.to_api_payload)

fdp.write_to_fdp(client: fdp)
