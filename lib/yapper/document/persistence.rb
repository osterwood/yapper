motion_require 'attribute'

module Yapper::Document
  module Persistence
    extend YapperSupport::Concern

    included do
      attr_accessor :attributes
      attr_accessor :changes
      attr_accessor :previous_changes
      attr_reader   :destroyed

      class_attribute :fields

      self.fields = {}.with_indifferent_access
    end

    module ClassMethods
      def create(*args)
        new(*args).tap { |doc| doc.save }
      end

      def delete_all
        db.execute do |txn|
          txn.removeAllObjectsInCollection(_type)
          self.dependent_destroys.each { |dependent_destroy| dependent_destroy.classify.constantize.delete_all }
        end
      end

      def field(name, options={})
        name = name.to_sym
        self.fields[name] = options

        define_method(name) do |*args, &block|
          self.attributes[name]
        end

        define_method("#{name}=".to_sym) do |*args, &block|
          self.set_attribute(name, args[0])
        end
      end

      def index(*args)
        db.index(self, args)
      end

      def search_index(*args)
        db.search_index(self, args)
      end

      def indexes
        db.indexes[self._type]
      end
    end

    def initialize(attrs={}, options={})
      super

      @new_record = options[:new].nil? ? true : options[:new]
      @changes = {}
      @queued_saves = []

      assign_attributes({:id => generate_id}, options) if @new_record
      assign_attributes(attrs, options)

      set_defaults

      if options[:pristine]
        self.changes = {}
      end

      self
    end

    def update_attributes(attrs, options={})
      self.assign_attributes(attrs, options)
      self.save(options)
    end

    def assign_attributes(attrs, options={})
      self.attributes ||= {}

      if options[:pristine]
        self.attributes = {}
      end

      if id = attrs[:id] || attrs['id']
        self.id = id
      end

      attrs.each do |k,v|
        next if k == :id

        if respond_to?("#{k}=")
          __send__("#{k}=", v) unless v.nil?
        else
          Log.debug "#{k} not defined on #{self.class}"
        end
      end
    end
    alias_method :attributes=, :assign_attributes

    def set_attribute(name, value)
      if self.class.fields[name][:type] == Time
        value = Time.parse(value) unless value.is_a?(Time)
      end
      # XXX This should not be set if the object was created from a
      # selection
      @changes[name.to_s] = value
      self.attributes[name.to_sym] = value
    end

    def reload
      reloaded = self.class.find(self.id)
      self.assign_attributes(reloaded.attributes, :pristine => true)
      self
    end

    def new_record?
      @new_record
    end

    def was_new?
      @was_new
    end

    def destroyed?
      !!@destroyed
    end

    def persisted?
      !new_record? && !destroyed?
    end

    def save(options={})
      db.execute do |txn|
        @queued_saves.each { |queued, queued_options| queued.save(queued_options) }

        run_callbacks 'save' do
          txn.setObject(stringify_keys(attributes), forKey: self.id, inCollection: _type)

          @was_new = @new_record
          @new_record = false
          @queued_saves = []

          self.previous_changes = self.changes
          self.changes = {}
        end

        self.touches.each { |touch| self.send(touch).try(:touch) }

        unless options[:embedded]
          # XXX Use middleware pattern instead of this ugliness
          sync_changes if defined? sync_changes
        end
      end

      true
    end

    def destroy(options={})
      db.execute do |txn|
        txn.removeObjectForKey(self.id, inCollection: _type)
        dependent_destroys.each { |dependent_destroy| self.send(dependent_destroy).each(&:destroy) }
      end

      # TODO Add spec to cover case when a relation is destroyed and touched
      self.touches.each { |touch| self.send(touch).touch if self.send(touch) }

      @destroyed = true
    end

    def touch
      db.execute { |txn| txn.touchObjectForKey(self.id, inCollection: self._type) }
    end

    private

    def generate_id
      BSON::ObjectId.generate
    end

    def set_defaults
      self.fields.each do |field, field_options|
        if __send__(field).nil?
          default = field_options[:default].respond_to?(:call) ? field_options[:default].call : field_options[:default]
          set_attribute(field, default)
        end
      end
    end
  end

  private

  # TODO Use deep_stringify_keys once https://github.com/kareemk/motion-support is merged upstream
  def stringify_keys(hash)
    result = {}
    hash.each do |key, value|
      result[key.to_s] = if value.is_a?(Hash)
        stringify_keys(value)
      elsif value.is_a?(Array)
        value.map { |v| v.is_a?(Hash) ? stringify_keys(v) : v }
      else
       value
      end
    end
    result
  end
end
