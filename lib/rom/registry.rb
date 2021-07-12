# frozen_string_literal: true

require "dry/container"
require "dry/core/memoizable"

require_relative "cache"
require_relative "constants"
require_relative "components/registry"
require_relative "initializer"
require_relative "resolver"
require_relative "inferrer"

module ROM
  class Registry
    extend Initializer

    include Dry::Core::Memoizable
    include Dry::Effects::Handler.Reader(:registry)
    include Enumerable

    MISSING_ELEMENT_ERRORS = {
      gateways: GatewayMissingError,
      schemas: SchemaMissingError,
      datasets: DatasetMissingError,
      relations: RelationMissingError,
      associations: RelationMissingError,
      commands: CommandNotFoundError,
      mappers: MapperMissingError
    }.freeze

    class Container
      include Dry::Container::Mixin
    end

    option :config, default: -> { Runtime.new.config }

    option :components, default: -> { Components::Registry.new(provider: self) }

    option :container, default: -> { Container.new }

    option :resolver, default: -> { Resolver.new(components) }

    option :inferrer, default: -> { Inferrer.new }

    option :notifications, optional: true

    option :type, optional: true

    option :path, default: -> { EMPTY_ARRAY }

    option :root, default: -> { self }

    option :opts, default: -> { EMPTY_HASH }

    # @api public
    def fetch(key, &block)
      case key
      when Symbol
        if root?(key)
          fetch(path.join("."), &block)
        elsif relation_scope?(key)
          scoped(key)
        else
          fetch([*path, key].join("."), &block)
        end
      when String
        return container[key] if container.key?(key)

        if associations? && !resolver.key?(key)
          components
            .associations(namespace: namespace)
            .detect { |assoc| key == "#{namespace}.#{assoc.definition.name}" }
            .then { |assoc| return fetch(assoc.as) if assoc }
        end

        with_registry(root) { build(key, &block) }.tap { |item|
          container.register(key, item)
        }
      when Array
        with_registry(self) { inferrer.call(key, type, **opts) }
      else
        if key.respond_to?(:to_sym)
          fetch(key.to_sym, &block)
        else
          raise MISSING_ELEMENT_ERRORS[type].new(key)
        end
      end
    rescue KeyError => e
      raise MISSING_ELEMENT_ERRORS[type].new(key)
    end
    alias_method :[], :fetch

    # @api public
    def infer(id, config)
      fetch(id) do
        components.add(type, config: {**config.to_h, id: id}).build
      end
    end

    # @api private
    def build(key, &block)
      resolver.call(key, &block)
    end

    # @api private
    def relation_scope?(key)
      if !key?(key) && (mappers? || commands?)
        relation_ids.include?(key)
      end
    end

    # @api private
    memoize def namespace
      path.join(".")
    end

    # @api private
    memoize def compiler
      inferrer.compiler(type, **opts)
    end

    # @api private
    def relation_ids
      components.relations.map(&:id)
    end

    # @api private
    def scoped(*scope, **options)
      with(path: path + scope, **options)
    end

    Components::CORE_TYPES.each do |type|
      define_method(type) do
        scoped(__method__, type: __method__)
      end

      define_method(:"#{type}?") do
        self.type == type
      end
    end

    # @api private
    def each(&block)
      keys.each { |key| yield(fetch(key)) }
    end

    # @api private
    def plugins
      config.plugins
    end

    # @api private
    def trigger(event, payload)
      notifications.trigger(event, payload) if notifications
    end

    # @api private
    def ids
      resolver.ids
    end

    # @api private
    def keys
      all = (resolver.keys + container.keys).uniq
      return all if path.empty?
      all.select { |key| key.start_with?(namespace) }
    end

    # @api private
    def key?(key)
      keys.include?([*path, key].join("."))
    end

    # @api private
    def root?(key)
      path.last == key && !mappers? # TODO: move mappers-specific behavior to rom/compat
    end

    # @api public
    def empty?
      keys.empty?
    end

    # @api private
    def inspect
      %(#<#{self.class} type=#{type || "root"} adapters=#{components.gateways.map(&:adapter)} keys=#{keys}>)
    end

    # Disconnect all gateways
    #
    # @example
    #   rom = ROM.container(:sql, 'sqlite://my_db.sqlite')
    #   rom.relations[:users].insert(name: "Jane")
    #   rom.disconnect
    #
    # @return [Hash<Symbol=>Gateway>] a hash with disconnected gateways
    #
    # @api public
    def disconnect
      container.keys.grep(/gateways/).each { |key| self[key].disconnect }
    end
  end
end
