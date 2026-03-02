module FDP
  class Client
    require 'rest-client'
    require 'json'

    attr_accessor :base_url, :email, :password, :token, :headers

    def initialize(base_url:, email: 'albert.einstein@example.com', password: 'password')
      @base_url = base_url
      @email = email
      @password = password
      begin
        response = RestClient.post(
          "#{base_url}/tokens",
          { email: email, password: password }.to_json,
          { content_type: :json, accept: :json }
        )

        token_data = JSON.parse(response.body)
        @token = token_data['token']
        warn "Authorization: Bearer #{token}"
      rescue RestClient::ExceptionWithResponse => e
        warn 'Error getting token:'
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        abort
      rescue StandardError => e
        warn "Unexpected error: #{e.message}"
        abort
      end

      @headers = {
        Authorization: "Bearer #{@token}",
        accept: :json,
        content_type: :json
      }
    end

    def list_current_schemas
      begin
        response = RestClient.get("#{base_url}/metadata-schemas", headers)
      rescue RestClient::ExceptionWithResponse => e
        warn 'Error fetching schemas:'
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        return []
      rescue StandardError => e
        warn "Unexpected error: #{e.message}"
        return []
      end
      j = JSON.parse(response.body)
      uuids = {}
      j.each do |entry|
        uuids[entry['name']] = { 'uuid' => entry['uuid'], 'definition' => entry['latest']['definition'] }
      end
      uuids
    end

    def retrieve_current_schemas # returns schema objects
      begin
        response = RestClient.get("#{base_url}/metadata-schemas", headers)
      rescue RestClient::ExceptionWithResponse => e
        warn 'Error fetching schemas:'
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        return []
      rescue StandardError => e
        warn "Unexpected error: #{e.message}"
        return []
      end
      j = JSON.parse(response.body)
      schemas = []
      j.each do |entry|
        # :name, :label, :description, :prefix, :definition, :parents, :children, :uuid, :version,:targetclasses
        schemas << FDP::Schema.new(
          name: entry['name'],
          label: entry['latest']['suggestedResourceName'],
          description: entry['latest']['description'],
          definition: entry['latest']['definition'],
          prefix: entry['latest']['suggestedUrlPrefix'] || nil,
          parents: entry['latest']['extendsSchemaUuids'] || [],
          children: entry['latest']['childSchemaUuids'] || [],
          uuid: entry['uuid'],
          version: entry['latest']['version'] || '1.0.0',
          targetclasses: entry['latest']['targetClassUris'] || ['http://www.w3.org/ns/dcat#Resource']
        )
      end
      schemas
    end

    def list_current_resources
      begin
        response = RestClient.get("#{base_url}/resource-definitions", headers)
      rescue RestClient::ExceptionWithResponse => e
        warn 'Error fetching resources definitions:'
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        return []
      rescue StandardError => e
        warn "Unexpected error: #{e.message}"
        return []
      end
      j = JSON.parse(response.body)
      uuids = {}
      j.each do |entry|
        # puts "- #{entry['name']}"
        uuids[entry['name']] = { 'uuid' => entry['uuid'] }
      end
      uuids
    end

    def retrieve_current_resources
      begin
        response = RestClient.get("#{base_url}/resource-definitions", headers)
      rescue RestClient::ExceptionWithResponse => e
        warn 'Error fetching resources definitions:'
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        return []
      rescue StandardError => e
        warn "Unexpected error: #{e.message}"
        return []
      end
      j = JSON.parse(response.body)
      resources = []
      j.each do |entry|
        resources << FDP::Resource.new(resourcejson: entry)
      end
      resources
    end

    def write_resource_definition(resource:)
      payload = resource.to_api_payload
      begin
        response = RestClient.post(
          "#{base_url}/metadata-schemas",
          payload.to_json,
          headers
        )
        result = JSON.parse(response.body)
        warn 'Success! New biobank shape created.'
        warn "UUID:       #{result['uuid']}"
        warn "Location:   #{result['location'] || '(not returned)'}"
        # warn "Full resp:  #{result.inspect}"
      rescue RestClient::ExceptionWithResponse => e
        warn "Upload failed (HTTP #{e.response.code}):"
        warn e.response.body
      rescue StandardError => e
        puts "Error: #{e.message}"
      end
      result
    end
  end
end
