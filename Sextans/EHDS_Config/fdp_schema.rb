module FDP
  class Schema
    attr_accessor :name, :label, :description, :prefix, :definition, :parents, :children, :uuid, :version,
                  :targetclasses

    def initialize(name:, label:, description:, definition:, prefix: nil, parents: [], children: [], uuid: nil,
                   targetclasses: ['http://www.w3.org/ns/dcat#Resource'], version: nil)
      @name = name
      @label = label
      @description = description
      @prefix = prefix
      @definition = definition
      @parents = parents
      @children = children
      @uuid = uuid
      @version = version
      @targetclasses = targetclasses
    end

    def to_api_payload
      {
        name: name, # short internal identifier (no spaces/special chars preferred)
        description: description,
        abstractSchema: true,
        suggestedResourceName: label, # display name in UI
        suggestedUrlPrefix: prefix, # optional, for auto-generating resource URLs
        published: true, # make it active for validation
        definition: definition, # the full Turtle string
        extendsSchemaUuids: parents, # array! inheritance chain
        version: version,
        targetClassUris: targetclasses,
        childSchemaUuids: children

      }.transform_keys { |k| k.to_s } # ensure string keys if API picky
    end
  end
end
