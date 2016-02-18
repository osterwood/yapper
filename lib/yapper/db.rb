motion_require 'yapper'
motion_require 'attribute'

class Yapper::DB
  @@queue = Dispatch::Queue.new("#{NSBundle.mainBundle.bundleIdentifier}.yapper.db")

  class_attribute :version

  def self.purge
    default.purge
  end

  def self.instance
    Dispatch.once { @@db = self.new(:name => name) }
    @@db
  end

  attr_reader :indexes

  def initialize(options)
    @options = options
    @name = options[:name]

    @indexes = {}
    @search_indexes = {}
    @views = {}

    self
  end

  def configure(&block)
    block.call(db)
  end

  def execute(&block)
    result = nil
    unless self.transaction
      self.transaction = Transaction.new(self)
      begin
        result = transaction.run(&block)
      ensure
        self.transaction = nil
      end
    else
      result = block.call(self.transaction.txn)
    end

    result
  end


  def read(&block)
    raise "Must only read db off of main thread otherwise use a execute for a read/write transaction" unless NSThread.isMainThread

    ReadTransaction.new(self).run(&block)
  end

  def purge
    Yapper::Settings.purge

    read_connection.endLongLivedReadTransaction

    @index_creation_required = true
    @search_index_creation_required = true
    @view_creation_required = true

    create_extensions!

    execute { |txn| txn.removeAllObjectsInAllCollections }
  end

  def transaction=(transaction)
    Thread.current[:yapper_transaction] = transaction
  end

  def transaction
    Thread.current[:yapper_transaction]
  end

  def index(model, args=[])
    options = args.extract_options!

    @index_creation_required = true
    @indexes[model._type] ||= {}

    args.each do |field|
      options = model.fields[field]; raise "#{model._type}:#{field} not defined" unless options
      type    = options[:type];      raise "#{model._type}:#{field} must define type as its indexed" if type.nil?

      @indexes[model._type][field] = { :type => type }
    end
  end

  def search_index(model, args=[])
    options = args.extract_options!

    @search_index_creation_required = true
    @search_indexes[model._type] ||= []

    args.each do |field|
      options = model.fields[field]; raise "#{model._type}:#{field} not defined" unless options

      @search_indexes[model._type] << field
    end
  end

  def view(view)
    @view_creation_required = true
    @views[view.name] = view
  end

  def connection
    create_extensions!

    Dispatch.once { @connection ||= db.newConnection }
    @connection
  end

  def read_connection
    create_extensions!

    Dispatch.once { @read_connection ||= db.newConnection }
    @read_connection
  end

  def db
    Dispatch.once { @db ||= YapDatabase.alloc.initWithPath(document_path) }
    @db
  end

  private

  def create_extensions!
    create_indexes!
    create_search_indexes!
    create_views!
  end

  def create_indexes!
    return unless @index_creation_required

    @@queue.sync do
      return unless @index_creation_required

      @indexes.each do |collection, fields|
        setup = YapDatabaseSecondaryIndexSetup.alloc.init

        fields.each do |field, options|
          type = case options[:type].to_s
                 when 'String'
                   YapDatabaseSecondaryIndexTypeText
                 when 'Integer'
                   YapDatabaseSecondaryIndexTypeInteger
                 when 'Time'
                   YapDatabaseSecondaryIndexTypeInteger
                 when 'Boolean'
                   YapDatabaseSecondaryIndexTypeInteger
                 else
                   raise "Invalid type #{type}"
                 end

          setup.addColumn(field, withType: type)
        end

        block = proc do |_dict, _collection, _key, _attrs|
          next unless _collection == collection

          if indexes = @indexes[_collection]
            indexes.each do |field, options|
              field = field.to_s
              if _collection == collection
                value = case options[:type].to_s
                        when 'Time'
                          _attrs[field].to_i
                        when 'Boolean'
                          _attrs[field] ? 1 : 0 unless _attrs[field].nil?
                        else
                          _attrs[field]
                        end
                value = NSNull if value.nil?
                _dict.setObject(value, forKey: field)
              end
            end
          end
        end

        unless Yapper::Settings.get("#{collection}_idx_defn") == @indexes[collection].to_canonical
          Yapper::Settings.set("#{collection}_idx_defn", @indexes[collection].to_canonical)
          configure do|yap|
            yap.unregisterExtensionWithName("#{collection}_IDX") if yap.registeredExtension("#{collection}_IDX")
          end
        end

        handler = YapDatabaseSecondaryIndexHandler.withObjectBlock(block)
        index_block = YapDatabaseSecondaryIndex.alloc.initWithSetup(setup, handler: handler, versionTag: '1')
        configure do |yap|
          yap.registerExtension(index_block, withName: "#{collection}_IDX")
        end
      end

      @index_creation_required = false
    end
  end

  def create_search_indexes!
    return unless @search_index_creation_required

    @@queue.sync do
      return unless @search_index_creation_required

      @search_indexes.each do |collection, fields|
        unless Yapper::Settings.get("#{collection}_sidx_defn") == @search_indexes[collection].to_canonical
          Yapper::Settings.set("#{collection}_sidx_defn", @search_indexes[collection].to_canonical)
          configure do|yap|
            yap.unregisterExtensionWithName("#{collection}_SIDX") if yap.registeredExtension("#{collection}_SIDX")
          end
        end

        block = proc do |_dict, _collection, _key, _attrs|
          next unless _collection == collection

          if fields = @search_indexes[_collection]
            fields.each do |field|
              field = field.to_s
              _dict.setObject(_attrs[field].to_s, forKey: field)
            end
          end
        end

        handler = YapDatabaseFullTextSearchHandler.withObjectBlock(block)
        index_block = YapDatabaseFullTextSearch.alloc.initWithColumnNames(fields.map(&:to_s), handler: handler, versionTag: '1')
        configure do |yap|
          yap.registerExtension(index_block, withName: "#{collection}_SIDX")
        end
      end

      @search_index_creation_required = false
    end
  end

  def create_views!
    return unless @view_creation_required

    @@queue.sync do
      return unless @view_creation_required

      @views.each do |view_name, view|
        unless Yapper::Settings.get("#{view_name}_views_defn") == view.version.to_s
          Yapper::Settings.set("#{view_name}_views_defn", view.version.to_s)
          configure do |yap|
            yap.unregisterExtensionWithName("#{view_name}_VIEW") if yap.registeredExtension("#{view_name}_VIEW")
          end
        end

        _block = proc do |_txn, _collection, _key, _attrs|
          view.group_for(_collection, _key, _attrs)
        end
        grouping_block = YapDatabaseViewGrouping.withObjectBlock(_block)

        _block = proc do |_txn, _group, _collection1, _key1, _obj1, _collection2, _key2, _obj2|
          view.sort_for(_group, _collection1, _key1, _obj1, _collection2, _key2, _obj2)
        end
        sorting_block = YapDatabaseViewSorting.withObjectBlock(_block)

        yap_view = YapDatabaseView.alloc.
          initWithGrouping(grouping_block,
                           sorting: sorting_block)

        configure do |yap|
          yap.registerExtension(yap_view, withName: "#{view_name}_VIEW")
        end
      end

      @view_creation_required = false
    end
  end

  def version
    Yapper::Settings.db_version || 0
  end

  def document_path
    NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true)[0] + "/yapper.#{version}.db"
  end

  class Transaction
    attr_accessor :txn

    def initialize(db)
      @db = db
    end

    def run(&block)
      result = nil
      txn_proc = proc do |_txn|
        @txn = _txn
        begin
          result = block.call(@txn)
        rescue Exception => e
          @txn.rollback
          result = e
        end
      end
      @db.connection.readWriteWithBlock(txn_proc)

      raise result if result.is_a?(Exception) || result.is_a?(NSException)
      result
    end
  end

  class ReadTransaction
    def initialize(db)
      @db = db
    end

    def run(&block)
      result = nil
      txn_proc = proc do |_txn|
        begin
          result = block.call(_txn)
        rescue Exception => e
          result = e
        end
      end
      @db.read_connection.readWithBlock(txn_proc)

      raise result if result.is_a?(Exception) || result.is_a?(NSException)
      result
    end
  end
end
