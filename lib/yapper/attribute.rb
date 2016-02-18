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

class Array
  # Extracts options from a set of arguments. Removes and returns the last
  # element in the array if it's a hash, otherwise returns a blank hash.
  def extract_options!
    if last.is_a?(Hash)
      pop
    else
      {}
    end
  end
end


class Class
  # Declare a class-level attribute whose value is inheritable by subclasses.
  # Subclasses can change their own value and it will not impact parent class.
  #
  #   class Base
  #     class_attribute :setting
  #   end
  #
  #   class Subclass < Base
  #   end
  #
  #   Base.setting = true
  #   Subclass.setting            # => true
  #   Subclass.setting = false
  #   Subclass.setting            # => false
  #   Base.setting                # => true
  #
  # In the above case as long as Subclass does not assign a value to setting
  # by performing <tt>Subclass.setting = _something_ </tt>, <tt>Subclass.setting</tt>
  # would read value assigned to parent class. Once Subclass assigns a value then
  # the value assigned by Subclass would be returned.
  #
  # This matches normal Ruby method inheritance: think of writing an attribute
  # on a subclass as overriding the reader method. However, you need to be aware
  # when using +class_attribute+ with mutable structures as +Array+ or +Hash+.
  # In such cases, you don't want to do changes in places but use setters:
  #
  #   Base.setting = []
  #   Base.setting                # => []
  #   Subclass.setting            # => []
  #
  #   # Appending in child changes both parent and child because it is the same object:
  #   Subclass.setting << :foo
  #   Base.setting               # => [:foo]
  #   Subclass.setting           # => [:foo]
  #
  #   # Use setters to not propagate changes:
  #   Base.setting = []
  #   Subclass.setting += [:foo]
  #   Base.setting               # => []
  #   Subclass.setting           # => [:foo]
  #
  # For convenience, a query method is defined as well:
  #
  #   Subclass.setting?       # => false
  #
  # Instances may overwrite the class value in the same way:
  #
  #   Base.setting = true
  #   object = Base.new
  #   object.setting          # => true
  #   object.setting = false
  #   object.setting          # => false
  #   Base.setting            # => true
  #
  # To opt out of the instance reader method, pass <tt>instance_reader: false</tt>.
  #
  #   object.setting          # => NoMethodError
  #   object.setting?         # => NoMethodError
  #
  # To opt out of the instance writer method, pass <tt>instance_writer: false</tt>.
  #
  #   object.setting = false  # => NoMethodError
  #
  # To opt out of both instance methods, pass <tt>instance_accessor: false</tt>.
  def class_attribute(*attrs)
    options = attrs.extract_options!
    # double assignment is used to avoid "assigned but unused variable" warning
    instance_reader = instance_reader = options.fetch(:instance_accessor, true) && options.fetch(:instance_reader, true)
    instance_writer = options.fetch(:instance_accessor, true) && options.fetch(:instance_writer, true)

    attrs.each do |name|
      define_singleton_method(name) { nil }
      define_singleton_method("#{name}?") { !!public_send(name) }

      ivar = "@#{name}"

      define_singleton_method("#{name}=") do |val|
        singleton_class.class_eval do
          remove_possible_method(name)
          define_method(name) { val }
        end

        if singleton_class?
          class_eval do
            remove_possible_method(name)
            define_method(name) do
              if instance_variable_defined? ivar
                instance_variable_get ivar
              else
                singleton_class.send name
              end
            end
          end
        end
        val
      end

      if instance_reader
        remove_possible_method name
        define_method(name) do
          if instance_variable_defined?(ivar)
            instance_variable_get ivar
          else
            self.class.public_send name
          end
        end
        define_method("#{name}?") { !!public_send(name) }
      end

      attr_writer name if instance_writer
    end
  end

  private
    def singleton_class?
      ancestors.first != self
    end
end