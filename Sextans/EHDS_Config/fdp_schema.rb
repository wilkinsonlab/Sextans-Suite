module FDP
  class Schema
    attr_accessor :name, :label, :description, :prefix, :definition, :parents, :children, :uuid, :version,
                  :targetclasses, :abstractschema

    def initialize(name:, label:, description:, definition:, prefix:, version:, targetclasses:, parents: [],
                   children: [], uuid: nil, abstractschema: false)
      # required
      @name = name
      @label = label
      @description = description
      @astractschema = abstractschema
      @prefix = prefix
      @definition = definition
      @version = version
      # optional
      @parents = parents
      @children = children
      @uuid = uuid
      @targetclasses = ['http://www.w3.org/ns/dcat#Resource'].append(targetclasses)
    end

    def to_api_payload
      {
        uuid: uuid, # include UUID for update if it exists, otherwise let the API generate a new one
        name: name, # short internal identifier (no spaces/special chars preferred)
        description: description,
        abstractSchema: abstractschema, # if you make it abstract, it won't be directly assignable to resources, only serve as a parent for other schemas. Useful for pure inheritance without validation, but not our use case here.
        suggestedResourceName: label, # display name in UI
        suggestedUrlPrefix: prefix, # optional, for auto-generating resource URLs
        published: true, # make it active for validation
        definition: definition, # the full Turtle string
        extendsSchemaUuids: parents, # array! inheritance chain
        version: version,
        targetClasses: targetclasses,
        childSchemaUuids: children

      }.transform_keys { |k| k.to_s } # ensure string keys if API picky
    end

    def write_to_fdp(client:)
      if uuid
        warn "Schema '#{name}' already has UUID #{uuid}. It will be overwritten with the new definition. If you want to keep the old version, make sure to change the name or remove the uuid before writing."
        overwrite_schema_in_fdp(client: client)
      else
        write_new_schema_to_fdp(client: client)
      end
    end

    def increment_version
      warn "Current version of schema '#{name}' is '#{version}'. Incrementing patch version for overwrite."
      major, minor, patch = version.split('.').map(&:to_i)
      patch += 5
      warn "NEW #{major}.#{minor}.#{patch}"
      "#{major}.#{minor}.#{patch}"
    end

    def overwrite_schema_in_fdp(client:)
      payload = to_api_payload
      newversion = increment_version
      payload['version'] = newversion # increment version for clarity,
      self.version = newversion # update the object's version for clarity, though the API actually ignores this
      warn "\n\n\nOVERWRITING schema '#{name}' with new definition:\n#{JSON.pretty_generate(payload)}\n\n\n"
      begin
        response = RestClient.put("#{client.base_url}/metadata-schemas/#{uuid}/draft", payload.to_json, client.headers)
        puts "Schema '#{name}' uploaded successfully as new draft (version #{version}) with UUID: #{JSON.parse(response.body)['definition']['uuid']}"
        self.uuid = JSON.parse(response.body)['uuid'] # update UUID after creation, though it should be the same
      rescue RestClient::ExceptionWithResponse => e
        warn "Error overwriting schema '#{name}':"
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        return nil
      rescue StandardError => e
        warn "Unexpected error while overwriting schema '#{name}': #{e.message}"
        return nil
      end
      publish(client: client) # don't fart aroind with drafts - those are only for the GUI and make no sense here
    end

    def write_new_schema_to_fdp(client:)
      payload = to_api_payload.delete('uuid')
      warn "\n\n\nWriting schema '#{name}' to FDP with payload:\n#{JSON.pretty_generate(payload)}\n\n\n"
      begin
        response = RestClient.post("#{client.base_url}/metadata-schemas", payload.to_json, client.headers)
        puts "Schema '#{name}' created successfully with UUID: #{JSON.parse(response.body)['uuid']}"
        self.uuid = JSON.parse(response.body)['uuid'] # update UUID after creation
      rescue RestClient::ExceptionWithResponse => e
        warn "Error creating schema '#{name}':"
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        return nil
      rescue StandardError => e
        warn "Unexpected error while creating schema '#{name}': #{e.message}"
        return nil
      end
      publish(client: client) # don't fart aroind with drafts - those are only for the GUI and make no sense here
    end

    def publish(client:)
      # publishing the version causes it to move out of draft and become active for validation.
      # {"major":"1",  # these three seem to be ignored by the API, it just uses the version field from the definition, but whatever
      # "minor":"0",
      # "patch":"0",
      # "description":"Custom SHACL shape for biobanks, extending the generic Resource",
      # "published":false,
      # "version":"1.0.0"}
      #
      publish_payload = {
        description: description,
        version: version,
        published: false # no, seriously... if you set this to true, it doesn't actually publish.
      }.to_json
      warn "\n\n\nPublishing schema '#{name}' with payload:\n#{JSON.pretty_generate(JSON.parse(publish_payload))}\n\n\n "

      begin
        response = RestClient.post("#{client.base_url}/metadata-schemas/#{uuid}/versions", publish_payload,
                                   client.headers)
        puts "Schema '#{name}' published successfully."
        response.body # this should be the schema details including the new version and published status
      rescue RestClient::ExceptionWithResponse => e
        warn "Error publishing schema '#{name}':"
        warn "Status: #{e.response.code}"
        warn "Body:   #{e.response.body}"
        nil
      rescue StandardError => e
        warn "Unexpected error while publishing schema '#{name}': #{e.message}"
        nil
      end
    end
  end
end
