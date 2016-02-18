###########################################################################
# Pulled from motion-support at:
#     https://github.com/rubymotion/motion-support
#
# There was a conflict with motion-require, and Yapper only needs the
# concern portion of motion-support.
###########################################################################


###########################################################################
#
# Copyright (c) 2005-2013 David Heinemeier Hansson
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
###########################################################################


module YapperSupport
  # A typical module looks like this:
  #
  #   module M
  #     def self.included(base)
  #       base.extend ClassMethods
  #       base.class_eval do
  #         scope :disabled, -> { where(disabled: true) }
  #       end
  #     end
  #
  #     module ClassMethods
  #       ...
  #     end
  #   end
  #
  # By using <tt>Yapper::Concern</tt> the above module could instead be
  # written as:
  #
  #   module M
  #     extend Yapper::Concern
  #
  #     included do
  #       scope :disabled, -> { where(disabled: true) }
  #     end
  #
  #     module ClassMethods
  #       ...
  #     end
  #   end
  #
  # Moreover, it gracefully handles module dependencies. Given a +Foo+ module
  # and a +Bar+ module which depends on the former, we would typically write the
  # following:
  #
  #   module Foo
  #     def self.included(base)
  #       base.class_eval do
  #         def self.method_injected_by_foo
  #           ...
  #         end
  #       end
  #     end
  #   end
  #
  #   module Bar
  #     def self.included(base)
  #       base.method_injected_by_foo
  #     end
  #   end
  #
  #   class Host
  #     include Foo # We need to include this dependency for Bar
  #     include Bar # Bar is the module that Host really needs
  #   end
  #
  # But why should +Host+ care about +Bar+'s dependencies, namely +Foo+? We
  # could try to hide these from +Host+ directly including +Foo+ in +Bar+:
  #
  #   module Bar
  #     include Foo
  #     def self.included(base)
  #       base.method_injected_by_foo
  #     end
  #   end
  #
  #   class Host
  #     include Bar
  #   end
  #
  # Unfortunately this won't work, since when +Foo+ is included, its <tt>base</tt>
  # is the +Bar+ module, not the +Host+ class. With <tt>Yapper::Concern</tt>,
  # module dependencies are properly resolved:
  #
  #   module Foo
  #     extend Yapper::Concern
  #     included do
  #       def self.method_injected_by_foo
  #         ...
  #       end
  #     end
  #   end
  #
  #   module Bar
  #     extend Yapper::Concern
  #     include Foo
  #
  #     included do
  #       self.method_injected_by_foo
  #     end
  #   end
  #
  #   class Host
  #     include Bar # works, Bar takes care now of its dependencies
  #   end
  module Concern
    def self.extended(base) #:nodoc:
      base.instance_variable_set("@_dependencies", [])
    end

    def append_features(base)
      if base.instance_variable_defined?("@_dependencies")
        base.instance_variable_get("@_dependencies") << self
        return false
      else
        return false if base < self
        @_dependencies.each { |dep| base.send(:include, dep) }
        super
        base.extend const_get("ClassMethods") if const_defined?("ClassMethods")
        base.class_eval(&@_included_block) if instance_variable_defined?("@_included_block")
      end
    end

    def included(base = nil, &block)
      if base.nil?
        @_included_block = block
      else
        super
      end
    end
  end
end