# Copyright (C) 2014  Ruby-GNOME2 Project Team
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

module Cairo
  class Context
    if method_defined?(:set_source_color)
      alias_method :set_source_not_gdk_color, :set_source_color
      def set_source_color(color)
        if color.is_a?(Gdk::Color)
          set_source_gdk_color(color)
        else
          set_source_not_gdk_color(color)
        end
      end
    else
      alias_method :set_source_color, :set_source_gdk_color
    end

    def source_color=(color)
      set_source_color(color)
      color
    end

    if method_defined?(:set_source_rgba)
      alias_method :set_source_not_gdk_rgba, :set_source_rgba
      def set_source_rgba(rgba, g=nil, b=nil, a=nil)
        case rgba
        when Gdk::RGBA
          set_source_gdk_rgba(rgba)
        when Array
          set_source_not_gdk_rgba(rgba)
        else
          r = rgba
          set_source_not_gdk_rgba([r, g, b, a])
        end
      end
    else
      alias_method :set_source_rgba, :set_source_gdk_rgba
    end

    def source_rgba=(rgba)
      set_source_rgba(rgba)
      rgba
    end

    alias_method :set_source_pixbuf_raw, :set_source_pixbuf
    def set_source_pixbuf(pixbuf, pixbuf_x=0, pixbuf_y=0)
      set_source_pixbuf_raw(pixbuf, pixbuf_x, pixbuf_y)
    end
  end
end
