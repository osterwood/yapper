motion_require 'yapper'

module Yapper::Config
  COLLECTION = '_config'
  extend self

  @@db_version = nil unless defined? @@db_version

  def self.db_version
    @@db_version || 0
  end

  def self.db_version=(db_version)
    @@db_version = db_version
  end

  def self.get(key)
    Yapper::DB.instance.execute do |txn|
      txn.objectForKey(key.to_s, inCollection: '_config')
    end
  end

  def self.set(key, value)
      Yapper::DB.instance.execute do |txn|
        txn.setObject(value, forKey: key, inCollection: COLLECTION)
      end
  end
end
