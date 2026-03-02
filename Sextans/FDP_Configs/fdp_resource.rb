module FDP
  class Resource
    attr_accessor :name, :uuid, :schemas, :description, :prefix, :targeturis, :children, :external_links, :client

    def initialize(client:, resourcejson: nil, schemas: [], description: nil, prefix: nil,
                   targeturis: [], children: [], external_links: [], uuid: nil, name: nil)
      @client = client
      if res = resourcejson # already parsed
        @uuid = res['uuid']
        @name = res['name']
        @prefix = res['urlPrefix']
        @schemas = res['metadataSchemaUuids']
        @targeturis = res['targetClassUris']
        @children = []
        res['children'].each do |childjson|
          @children << ResourceChild.new(childjson: childjson)
        end
        @external_links = []
        res['externalLinks'].each do |linkjson|
          @external_links << ResourceExternalLink.new(linkjson: linkjson)
        end
        @description = res['description'] || 'No description provided'
      else
        validate_name(name: name) # throws error if it exists
        @name = name
        @uuid = uuid # this will be rare
        @schemas = schemas
        @description = description
        @prefix = prefix
        @targeturis = targeturis
        @children = children # must be objects of class ResourceChild
        @external_links = external_links # must be objects of class ResourceExternalLink
      end
    end

    def validate_name(name:)
      return unless @client.list_current_resources[name]

      raise ArgumentError,
            'Your assigned resource name #{name} already exists - you MUST edit the existing record rather than create a new one'
    end

    def to_api_payload
      {
        uuid: uuid,
        name: name, # short internal identifier (no spaces/special chars preferred)
        urlPrefix: prefix, # optional, for auto-generating resource URLs
        metadataSchemaUuids: schemas, # array of schema UUIDs that apply to this resource
        targetClassUris: targeturis, # array of RDF class URIs this resource represents
        children: children.map(&:to_api_payload), # array of child resource definitions
        externalLinks: external_links.map(&:to_api_payload), # array of external links
        description: description # optional human-readable description
      }.transform_keys { |k| k.to_s } # ensure string keys if API picky
    end

    def write_to_fdp(client:)
      if uuid.to_s.strip.empty?
        write_new_resource(client: client)
      else
        replace_existing_resource(client: client)
      end
    end

    def write_new_resource(client:)
      warn "in write_new_resource method for resource '#{name}'"

      # This method can be used to create a new resource without needing to provide a full client object
      # It will use the FDP::Client class internally to handle the API interaction
      payload = to_api_payload
      payload.delete(:uuid) # Ensure UUID is not sent when creating a new resource
      begin
        response = RestClient.post("#{client.base_url}/resource-definitions", payload.to_json, client.headers)
        puts "Resource '#{name}' updated successfully."
        self.uuid = JSON.parse(response.body)['uuid']
      rescue RestClient::ExceptionWithResponse => e
        warn "Error updating resource '#{name}':"
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
      rescue StandardError => e
        warn "Unexpected error while updating resource '#{name}': #{e.message}"
      end
    end

    def replace_existing_resource(client:)
      warn "in replace methidod for resource '#{name}' with UUID: #{uuid}"
      # This method can be used to replace an existing resource definition by its UUID
      # It will use the FDP::Client class internally to handle the API interaction
      payload = to_api_payload
      begin
        RestClient.put("#{client.base_url}/resource-definitions/#{uuid}", payload.to_json, client.headers)
        puts "Resource '#{name}' updated successfully."
      rescue RestClient::ExceptionWithResponse => e
        warn "Error updating resource '#{name}':"
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
      rescue StandardError => e
        warn "Unexpected error while updating resource '#{name}': #{e.message}"
      end
    end
  end

  class ResourceChild
    attr_accessor :resourceDefinitionUuid, :relationUri, :listViewTitle, :listViewTagsUri, :listViewMetadata

    def initialize(childjson: nil, resourceDefinitionUuid: nil, relationUri: nil, listViewTitle: nil, listViewTagsUri: nil,
                   listViewMetadata: [])
      if res = childjson # already parsed
        @resourceDefinitionUuid = res['resourceDefinitionUuid']
        @relationUri = res['relationUri']
        @listViewTitle = res['listView']['title'] || 'No title provided'
        @listViewTagsUri = res['listView']['tagsUri'] || nil
        @listViewMetadata = res['listView']['metadata'] || []
      else
        unless resourceDefinitionUuid && relationUri # these are the minimum required fields for a child resource
          raise ArgumentError, 'resourceDefinitionUuid and relationUri are required for a ResourceChild'
        end

        @resourceDefinitionUuid = resourceDefinitionUuid
        @relationUri = relationUri
        @listViewTitle = listViewTitle
        @listViewTagsUri = listViewTagsUri
        @listViewMetadata = listViewMetadata
      end
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

  class ResourceExternalLink
    attr_accessor :title, :propertyuri

    def initialize(linkjson: nil, title: nil, propertyuri: nil)
      if res = linkjson # already parsed
        @title = res['title']
        @propertyuri = res['propertyUri']
      else
        @title = title
        @propertyuri = propertyuri
      end
    end

    def to_api_payload
      {
        title: title,
        propertyUri: propertyuri
      }.transform_keys { |k| k.to_s } # ensure string keys if API picky
    end
  end
end
