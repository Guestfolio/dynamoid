# frozen_string_literal: true

module Dynamoid #:nodoc:
  module Criteria
    class KeyFieldsDetector

      class Query
        def initialize(query_hash)
          @query_hash = query_hash
          @fields_with_operator = query_hash.keys.map(&:to_s)
          @fields = query_hash.keys.map(&:to_s).map { |s| s.split('.').first }
        end

        def contain?(field_name)
          @fields.include?(field_name.to_s)
        end

        def contain_with_eq_operator?(field_name)
          @fields_with_operator.include?(field_name.to_s)
        end
      end

      def initialize(query, source)
        @query = query
        @source = source
        @query = Query.new(query)
        @result = find_keys_in_query
      end

      def key_present?
        @result.present?
      end

      def hash_key
        @result && @result[:hash_key]
      end

      def range_key
        @result && @result[:range_key]
      end

      def index_name
        @result && @result[:index_name]
      end

      private

      def find_keys_in_query
        match_table_and_sort_key ||
          match_local_secondary_index ||
          match_global_secondary_index_and_sort_key ||
          match_table ||
          match_global_secondary_index
      end

      # Use table's default range key
      def match_table_and_sort_key
        return unless @query.contain_with_eq_operator?(@source.hash_key)
        return unless @source.range_key

        if @query.contain?(@source.range_key)
          {
            hash_key: @source.hash_key,
            range_key: @source.range_key
          }
        end
      end

      # See if can use any local secondary index range key
      # Chooses the first LSI found that can be utilized for the query
      def match_local_secondary_index
        return unless @query.contain_with_eq_operator?(@source.hash_key)

        lsi = @source.local_secondary_indexes.values.find do |lsi|
          @query.contain?(lsi.range_key)
        end

        if lsi.present?
          {
            hash_key: @source.hash_key,
            range_key: lsi.range_key,
            index_name: lsi.name,
          }
        end
      end

      # See if can use any global secondary index
      # Chooses the first GSI found that can be utilized for the query
      # GSI with range key involved into query conditions has higher priority
      # But only do so if projects ALL attributes otherwise we won't
      # get back full data
      def match_global_secondary_index_and_sort_key
        gsi = @source.global_secondary_indexes.values.find do |gsi|
          @query.contain_with_eq_operator?(gsi.hash_key) && gsi.projected_attributes == :all &&
            @query.contain?(gsi.range_key)
        end

        if gsi.present?
          {
            hash_key: gsi.hash_key,
            range_key: gsi.range_key,
            index_name: gsi.name,
          }
        end
      end

      def match_table
        return unless @query.contain_with_eq_operator?(@source.hash_key)

        {
          hash_key: @source.hash_key,
        }
      end

      def match_global_secondary_index
        gsi = @source.global_secondary_indexes.values.find do |gsi|
          @query.contain_with_eq_operator?(gsi.hash_key) && gsi.projected_attributes == :all
        end

        if gsi.present?
          {
            hash_key: gsi.hash_key,
            range_key: gsi.range_key,
            index_name: gsi.name,
          }
        end
      end
    end
  end
end
