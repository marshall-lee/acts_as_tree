module ActsAsTree
  module PG
    class ObjectWithPreloadedParent < ActiveSupport::ProxyObject
      def initialize(object, parent)
        @object = object
        @parent = parent
      end

      def parent
        @parent
      end

      def respond_to_missing?(method, include_private = false)
        super || @object.respond_to?(method)
      end

      def method_missing(method, *args, &block)
        return super unless @object.respond_to?(method)
        @object.send(method, *args, &block)
      end
    end

    class ObjectWithPreloadedChildren < ActiveSupport::ProxyObject
      def initialize(object, children)
        @object = object
        @children = children
      end

      def children
        records = @children
        @object.children.extending do
          define_method :loaded? do
            true
          end
        end.instance_eval do
          @records = records
          self
        end
      end

      def respond_to_missing?(method, include_private = false)
        super || @object.respond_to?(method)
      end

      def method_missing(method, *args, &block)
        return super unless @object.respond_to?(method)
        @object.send(method, *args, &block)
      end
    end

    def self.ancestors(object, model, foreign_key)
      table = model.arel_table
      primary_key = model.primary_key.to_sym

      tmp_name = "_#{model.table_name}_ancestors"
      tmp_table = Arel::Table.new(tmp_name, model)

      non_recursive_part = model.where(table[primary_key].eq object[foreign_key]).select(table[primary_key]).select(table[foreign_key]).arel.ast
      recursive_part = model.where(table[primary_key].eq tmp_table[foreign_key]).select(table[primary_key]).select(table[foreign_key]).from([table, tmp_table]).arel.ast
      cte = Arel::Nodes::Union.new(non_recursive_part, recursive_part)
      cte = Arel::Nodes::As.new(Arel::Nodes::SqlLiteral.new(tmp_name), cte)

      scope = model.from([table, tmp_table]).where(table[primary_key].eq tmp_table[primary_key])
      scope.arel.with(:recursive, cte)

      by_id = scope.index_by(&:id)
      node, nodes = object, []
      nodes << node = ObjectWithPreloadedParent.new(by_id[node[foreign_key]], node) while node[foreign_key]
      nodes
    end

    def self.descendants(object, model, foreign_key, order)
      table = model.arel_table
      primary_key = model.primary_key.to_sym

      tmp_name = "_#{model.table_name}_descendants"
      tmp_table = Arel::Table.new(tmp_name, model)

      non_recursive_part = model.where(table[foreign_key].eq object[primary_key]).select(table[primary_key]).select(table[foreign_key]).arel.ast
      recursive_part = model.where(table[foreign_key].eq tmp_table[primary_key]).select(table[primary_key]).select(table[foreign_key]).from([table, tmp_table]).arel.ast
      cte = Arel::Nodes::Union.new(non_recursive_part, recursive_part)
      cte = Arel::Nodes::As.new(Arel::Nodes::SqlLiteral.new(tmp_name), cte)

      scope = model.from([table, tmp_table]).where(table[primary_key].eq tmp_table[primary_key])
      scope = scope.order(order) if order
      scope.arel.with(:recursive, cte)

      records = scope.to_a
      return [] if records.empty?

      id_to_children = {}
      records.each do |node|
        key = node[foreign_key]
        (id_to_children[key] ||= []).push(node)
      end
      id_to_children.each_value do |children|
        children.map! do |obj|
          ObjectWithPreloadedChildren.new(obj, id_to_children[obj.id] || [])
        end
      end

      object = ObjectWithPreloadedChildren.new(object, id_to_children[object.id])

      nodes = []
      queue = [object]
      until queue.empty?
        node = queue.shift
        children = node.children
        queue.unshift(*children)
        nodes.concat(node.children.map { |child| ObjectWithPreloadedParent.new(child, node) })
      end

      nodes
    end
  end
end
