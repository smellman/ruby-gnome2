# Copyright (C) 2012-2013  Ruby-GNOME2 Project Team
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

module GObjectIntrospection
  class Loader
    class << self
      def load(namespace, base_module, options={})
        loader = new(base_module)
        loader.version = options[:version]
        loader.load(namespace)
      end
    end

    attr_accessor :version
    def initialize(base_module)
      @base_module = base_module
      @version = nil
    end

    def load(namespace)
      repository = Repository.default
      repository.require(namespace, @version)
      pre_load(repository, namespace)
      repository.each(namespace) do |info|
        load_info(info)
      end
      post_load(repository, namespace)
    end

    private
    def pre_load(repository, namespace)
    end

    def post_load(repository, namespace)
    end

    def load_info(info)
      case info
      when FunctionInfo
        load_function_info(info)
      when StructInfo
        load_struct_info(info)
      when BoxedInfo
        load_boxed_info(info)
      when FlagsInfo
        load_flags_info(info)
      when EnumInfo
        load_enum_info(info)
      when ObjectInfo
        load_object_info(info)
      when InterfaceInfo
        load_interface_info(info)
      when ConstantInfo
        load_constant_info(info)
      when UnionInfo
        load_union_info(info)
      end
    end

    def load_function_info(info)
      name = rubyish_method_name(info)
      define_module_function(@base_module, name, info)
    end

    def define_module_function(target_module, name, function_info)
      unlock_gvl = should_unlock_gvl?(function_info, target_module)
      validate = lambda do |arguments|
        method_name = "#{target_module}\#.#{name}"
        validate_arguments(function_info, method_name, arguments)
      end
      target_module.module_eval do
        define_method(name) do |*arguments, &block|
          validate.call(arguments, &block)
          function_info.invoke({
                                 :arguments => arguments,
                                 :unlock_gvl => unlock_gvl,
                               },
                               &block)
        end
        module_function(name)
      end
    end

    def define_singleton_method(klass, name, info)
      unlock_gvl = should_unlock_gvl?(info, klass)
      validate = lambda do |arguments|
        validate_arguments(info, "#{klass}.#{name}", arguments)
      end
      singleton_class = (class << klass; self; end)
      singleton_class.__send__(:define_method, name) do |*arguments, &block|
        validate.call(arguments, &block)
        if block.nil? and info.require_callback?
          Enumerator.new(self, name, *arguments)
        else
          info.invoke({
                        :arguments => arguments,
                        :unlock_gvl => unlock_gvl,
                      },
                      &block)
        end
      end
    end

    def define_struct(info, options={})
      if info.gtype == GLib::Type::NONE
        klass = self.class.define_struct(info.size, info.name, @base_module,
                                         :parent => options[:parent])
      else
        klass = self.class.define_class(info.gtype, info.name, @base_module,
                                        :parent => options[:parent],
                                        :size   => info.size)
      end
      load_fields(info, klass)
      load_methods(info, klass)
    end

    def load_struct_info(info)
      return if info.gtype_struct?

      define_struct(info)
    end

    def define_boxed(info)
      klass = self.class.define_class(info.gtype, info.name, @base_module)
      _ = klass # TODO: Remove me. It is just for suppressing a warning.
      # TODO
      # load_fields(info, klass)
      # load_methods(info, klass)
    end

    def load_boxed_info(info)
      define_boxed(info)
    end

    def load_enum_value(value_info, enum_module)
      enum_module.const_set(value_info.name.upcase, value_info.value)
    end

    def define_enum(info)
      self.class.define_class(info.gtype,
                              enum_class_name(info),
                              @base_module)
    end

    def enum_class_name(info)
      info.name
    end

    def define_error(info)
      self.class.define_error(info.error_domain,
                              error_class_name(info),
                              @base_module,
                              :parent => error_parent_class(info),
                              :gtype => info.gtype)
    end

    def error_class_name(info)
      info.name
    end

    def error_parent_class(info)
      nil
    end

    def load_enum_info(info)
      if info.gtype == GLib::Type::NONE
        enum_module = Module.new
        info.values.each do |value_info|
          load_enum_value(value_info, enum_module)
        end
        @base_module.const_set(info.name, enum_module)
      else
        if info.error_domain
          define_error(info)
        else
          define_enum(info)
        end
      end
    end

    def load_flag_value(value_info, flags_module)
      flags_module.const_set(value_info.name.upcase, value_info.value)
    end

    def load_flags_info(info)
      if info.gtype == GLib::Type::NONE
        flags_module = Module.new
        info.values.each do |value_info|
          load_flag_value(value_info, flags_module)
        end
        @base_module.const_set(info.name, flags_module)
      else
        self.class.define_class(info.gtype, info.name, @base_module)
      end
    end

    def load_object_info(info)
      klass = self.class.define_class(info.gtype, info.name, @base_module)
      load_fields(info, klass)
      load_methods(info, klass)
    end

    def load_fields(info, klass)
      info.n_fields.times do |i|
        field_info = info.get_field(i)
        load_field(info, i, field_info, klass)
      end
    end

    def load_field(info, i, field_info, klass)
      name = field_info.name
      flags = field_info.flags

      if flags.readable?
        if field_info.type.tag == TypeTag::BOOLEAN
          reader_method_name = "#{name}?"
        else
          reader_method_name = name
        end
        klass.__send__(:define_method, reader_method_name) do ||
          info.get_field_value(self, i)
        end
      end

      if flags.writable?
        klass.__send__(:define_method, "#{name}=") do |value|
          info.set_field_value(self, i, value)
        end
      end
    end

    def load_methods(info, klass)
      grouped_methods = info.methods.group_by do |method_info|
        method_info.class
      end
      grouped_methods.each do |method_info_class, method_infos|
        next if method_infos.empty?
        case method_infos.first
        when ConstructorInfo
          load_constructor_infos(method_infos, klass)
        when MethodInfo
          load_method_infos(method_infos, klass)
        when FunctionInfo
          load_function_infos(method_infos, klass)
        else
          raise "TODO: #{method_info_class}"
        end
      end
    end

    def load_constructor_infos(infos, klass)
      return if infos.empty?

      validate = lambda do |info, method_name, arguments|
        validate_arguments(info, "#{klass}\##{method_name}", arguments)
      end
      infos.each do |info|
        name = "initialize_#{info.name}"
        unlock_gvl = should_unlock_gvl?(info, klass)
        klass.__send__(:define_method, name) do |*arguments, &block|
          validate.call(info, name, arguments, &block)
          info.invoke({
                        :receiver  => self,
                        :arguments => arguments,
                        :unlock_gvl => unlock_gvl,
                      },
                      &block)
        end
        klass.__send__(:private, name)
      end

      find_info = lambda do |arguments|
        find_suitable_callable_info(infos, arguments)
      end
      klass.__send__(:define_method, "initialize") do |*arguments, &block|
        info = find_info.call(arguments, &block)
        __send__("initialize_#{info.name}", *arguments, &block)
      end
    end

    def validate_arguments(info, method_name, arguments)
      n_in_args = info.n_in_args
      n_required_in_args = info.n_required_in_args
      return if (n_required_in_args..n_in_args).cover?(arguments.size)

      detail = "#{arguments.size} for "
      if n_in_args == n_required_in_args
        detail << "#{n_in_args}"
      else
        detail << "#{n_required_in_args}..#{n_in_args}"
      end
      message = "#{method_name}: wrong number of arguments (#{detail})"
      raise ArgumentError, message
    end

    def find_suitable_callable_info(infos, arguments)
      min_n_args = nil
      max_n_args = nil
      candidate_infos = []
      infos.each do |info|
        n_in_args = info.n_in_args
        n_required_in_args = info.n_required_in_args
        if (n_required_in_args..n_in_args).cover?(arguments.size)
          candidate_infos << info
        end
        min_n_args = [min_n_args || n_required_in_args, n_required_in_args].min
        max_n_args = [max_n_args || n_in_args, n_in_args].max
      end

      if candidate_infos.size == 1
        return candidate_infos.first
      elsif candidate_infos.size > 1
        candidate_info = candidate_infos.find do |info|
          in_arg_infos = info.in_args
          arguments.each.with_index.all? do |argument, i|
            match_argument?(in_arg_infos[i], argument)
          end
        end
        return candidate_info || candidate_infos.first
      end

      detail = "#{arguments.size} for #{min_n_args}"
      if min_n_args < max_n_args
        detail << "..#{max_n_args}"
      end
      raise ArgumentError, "wrong number of arguments (#{detail})"
    end

    def match_argument?(arg_info, argument)
      case arg_info.type.tag
      when TypeTag::UTF8
        argument.is_a?(String)
      else
        # TODO
        false
      end
    end

    def rubyish_method_name(function_info, options={})
      name = function_info.name
      if options[:prefix]
        name = name.gsub(/\A#{Regexp.escape(options[:prefix])}/, "")
      end
      return_type = function_info.return_type
      if return_type.tag == GObjectIntrospection::TypeTag::BOOLEAN
        case name
        when /\A(?:is|get_is)_/
          "#{$POSTMATCH}?"
        when /\Aget_/
          if function_info.n_in_args.zero?
            "#{$POSTMATCH}?"
          else
            name
          end
        when /\A(?:has|use)_/
          "#{name}?"
        else
          name
        end
      elsif /\Aget_/ =~ name and function_info.n_in_args.zero?
        $POSTMATCH
      else
        case name
        when "to_string"
          "to_s"
        when "foreach"
          "each"
        else
          name
        end
      end
    end

    def should_unlock_gvl?(function_info, klass)
      false
    end

    def load_method_infos(infos, klass)
      infos.each do |info|
        method_name = rubyish_method_name(info)
        load_method_info(info, klass, method_name)
      end
    end

    def load_method_info(info, klass, method_name)
      define_method(info, klass, method_name)
      define_equal_style_setter(info, klass, method_name)
    end

    def define_method(info, klass, method_name)
      unlock_gvl = should_unlock_gvl?(info, klass)
      validate = lambda do |arguments|
        validate_arguments(info, "#{klass}\##{method_name}", arguments)
      end
      if klass.method_defined?(method_name) and
          klass.instance_method(method_name).owner == klass
        klass.__send__(:remove_method, method_name)
      end
      function_info_p = (info.class == FunctionInfo)
      klass.__send__(:define_method, method_name) do |*arguments, &block|
        arguments = [self] + arguments if function_info_p
        validate.call(arguments, &block)
        if block.nil? and info.require_callback?
          to_enum(method_name, *arguments)
        else
          options = {
            :arguments => arguments,
            :unlock_gvl => unlock_gvl,
          }
          options[:receiver] = self unless function_info_p
          info.invoke(options, &block)
        end
      end
    end

    def define_equal_style_setter(info, klass, method_name)
      if /\Aset_/ =~ method_name and info.n_args == 1
        setter_method_name = "#{$POSTMATCH}="
        if klass.method_defined?(setter_method_name) and
            klass.instance_method(setter_method_name).owner == klass
          klass.__send__(:remove_method, setter_method_name)
        end
        klass.__send__(:alias_method, setter_method_name, method_name)
      end
    end

    def load_function_infos(infos, klass)
      infos.each do |info|
        name = rubyish_method_name(info)
        next if name == "new"
        next if name == "alloc"
        define_singleton_method(klass, name, info)
      end
    end

    def load_interface_info(info)
      interface_module =
        self.class.define_interface(info.gtype, info.name, @base_module)
      load_methods(info, interface_module)
    end

    def load_constant_info(info)
      @base_module.const_set(info.name, info.value)
    end

    def load_union_info(info)
      klass = self.class.define_class(info.gtype, info.name, @base_module)
      load_fields(info, klass)
      load_methods(info, klass)
    end
  end
end
