module ActsAsTree
  module PG
    def self.ancestors(object, model, foreign_key)
      table = model.arel_table
      primary_key = model.primary_key.to_sym

      tmp_name = "_#{model.table_name}_ancestors"
      tmp_table = Arel::Table.new(tmp_name, model)

      non_recursive_part = model.where(table[primary_key].eq object[foreign_key]).select(table[primary_key]).select(table[foreign_key]).arel.ast
      recursive_part = model.where(table[primary_key].eq tmp_table[foreign_key]).select(table[primary_key]).select(table[foreign_key]).from([table, tmp_table]).arel.ast
      cte = Arel::Nodes::Union.new(non_recursive_part, recursive_part)
      cte = Arel::Nodes::As.new Arel::Nodes::SqlLiteral.new(tmp_name), cte

      scope = model.from([table, tmp_table]).where(table[primary_key].eq tmp_table[primary_key])
      scope.arel.with(:recursive, cte)

      by_id = scope.index_by(&:id)
      node, nodes = object, []
      nodes << node = by_id[node[foreign_key]] while node[foreign_key]
      nodes
    end
  end
end
