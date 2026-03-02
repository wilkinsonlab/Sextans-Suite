module FDP
  class Resource
    attr_accessor :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links

    def initialize(resourcejson:)
      res = resourcejson # already parsed
      @uuid = res['uuid']
      @name = res['name']
      @prefix = res['urlPrefix']
      @schemas = res['metadataSchemaUuids']
      @targeturis = res['targetClassUris']
      @children = []
      res['children'].each do |childjson|
        @children << ResourceChild.new(childjson: childjson)
      end
      @external_links = res['externalLinks']
    end

    def to_api_payload
      {
        uuid: uuid,
        name: name, # short internal identifier (no spaces/special chars preferred)
        urlPrefix: prefix, # optional, for auto-generating resource URLs
        metadataSchemaUuids: schemas, # array of schema UUIDs that apply to this resource
        targetClassUris: targeturis, # array of RDF class URIs this resource represents
        children: children.map(&:to_api_payload), # array of child resource definitions
        externalLinks: external_links # array of { label: '', url: '' } hashes for UI display
      }.transform_keys { |k| k.to_s } # ensure string keys if API picky
    end

    def write_to_fdp(client:)
      payload = to_api_payload
      begin
        response = RestClient.post("#{client.base_url}/resource-definitions", payload.to_json, client.headers)
        puts "Resource '#{name}' created successfully with UUID: #{JSON.parse(response.body)['uuid']}"
        self.uuid = JSON.parse(response.body)['uuid'] # update UUID after creation
      rescue RestClient::ExceptionWithResponse => e
        warn "Error creating resource '#{name}':"
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
      rescue StandardError => e
        warn "Unexpected error while creating resource '#{name}': #{e.message}"
      end
    end
  end

  class ResourceChild
    attr_accessor :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata

    def initialize(childjson:)
      res = childjson # already parsed
      @resourceDefinitionUuid = res['resourceDefinitionUuid']
      @relationUri = res['relationUri']
      @listViewTitle = res['listView']['title'] || 'No title provided'
      @listViewTagsUri = res['listView']['tagsUri'] || nil
      @listViewMetadata = res['listView']['metadata'] || []
    end

    def to_api_payload
      {
        resourceDefinitionUuid: resourceDefinitionUuid,
        relationUri: relationUri,
        listView: {
          title: listViewTitle,
          tagsUri: listViewTagsUri,
          metadata: listViewMetadata
        }
      }.transform_keys { |k| k.to_s } # ensure string keys if API picky
    end
  end
end
