# frozen_string_literal: true

#
# Copyright (C) 2014 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

module Importers
  class RubricImporter < Importer
    self.item_class = Rubric

    def self.process_migration(data, migration)
      rubrics = data["rubrics"] || []
      migration.outcome_to_id_map ||= {}
      migration.copied_external_outcome_map ||= {}
      rubrics.each do |rubric|
        next unless migration.import_object?("rubrics", rubric["migration_id"])

        begin
          import_from_migration(rubric, migration)
        rescue
          migration.add_import_warning(t("#migration.rubric_type", "Rubric"), rubric[:title], $!)
        end
      end
    end

    def self.import_from_migration(hash, migration, item = nil)
      context = migration.context
      hash = hash.with_indifferent_access
      return nil if hash[:migration_id] && hash[:rubrics_to_import] && !hash[:rubrics_to_import][hash[:migration_id]]

      rubric = nil
      if !item && hash[:external_identifier]
        rubric = context.available_rubric(hash[:external_identifier]) unless migration.cross_institution?

        unless rubric
          Rails.logger.warn("The external Rubric couldn't be found for \"#{hash[:title]}\", creating a copy.")
        end
      end

      if rubric
        item = rubric
      else
        item ||= Rubric.where(context_id: context, context_type: context.class.to_s, id: hash[:id]).first
        item ||= Rubric.where(context_id: context, context_type: context.class.to_s, migration_id: hash[:migration_id]).first if hash[:migration_id]

        # avoid override a rubric used for grading
        if item&.rubric_assessments&.any?
          return migration.add_import_warning(
            t("#migration.rubric_type", "Rubric"),
            hash[:title],
            I18n.t("A rubric that has been used for grading cannot be overwritten.")
          )
        end

        item ||= Rubric.new(context:)
        item.migration_id = hash[:migration_id]
        item.workflow_state = "active" if item.deleted?
        item.title = hash[:title]
        item.populate_rubric_title # just in case
        item.description = hash[:description]
        item.points_possible = hash[:points_possible].to_f
        item.read_only = hash[:read_only] unless hash[:read_only].nil?
        item.reusable = hash[:reusable] unless hash[:reusable].nil?
        item.public = hash[:public] unless hash[:public].nil?
        item.hide_score_total = hash[:hide_score_total] unless hash[:hide_score_total].nil?
        item.free_form_criterion_comments = hash[:free_form_criterion_comments] unless hash[:free_form_criterion_comments].nil?

        item.data = hash[:data]
        item.data.each do |crit|
          if crit[:learning_outcome_migration_id].present?
            if migration.respond_to?(:outcome_to_id_map) && (id = migration.outcome_to_id_map[crit[:learning_outcome_migration_id]])
              crit[:learning_outcome_id] = id
            elsif (lo = context.created_learning_outcomes.where(migration_id: crit[:learning_outcome_migration_id]).first)
              crit[:learning_outcome_id] = lo.id
            end
          elsif crit[:learning_outcome_external_identifier].present?
            # link an account outcome
            lo = context.available_outcome(crit[:learning_outcome_external_identifier]) unless migration.cross_institution?

            # link the copy of an account outcome that isn't available in the destination context
            unless lo
              mig_id = migration.copied_external_outcome_map[crit[:learning_outcome_external_identifier]]
              lo = context.created_learning_outcomes.find_by(migration_id: mig_id) if mig_id
            end

            crit[:learning_outcome_id] = lo.id if lo
          end
          crit.delete(:learning_outcome_migration_id)
          crit.delete(:learning_outcome_external_identifier)
        end

        item.skip_updating_points_possible = true
        item.update_mastery_scales(false)
        migration.add_imported_item(item)
        item.save!
      end

      process_rubric_association(context, migration, item)
      track_metrics(migration)

      item
    end

    def self.process_rubric_association(context, migration, item)
      associate_with = context
      opts = { skip_updating_rubric_association_count: true }

      if context.is_a?(Course) && migration.migration_settings[:associate_with_assignment_id].present?
        assignment = context.assignments.where(id: migration.migration_settings[:associate_with_assignment_id]).first

        if assignment && assignment.rubric_association.blank?
          associate_with = assignment
          opts[:purpose] = "grading"
        end
      end

      association = if associate_with.is_a?(Assignment)
                      associate_with.rubric_association
                    else
                      associate_with.rubric_associations.where(rubric_id: item).first
                    end

      if association
        unless association.bookmarked
          association.bookmarked = true
          association.save!
        end
      else
        item.associate_with(associate_with, context, opts)
      end
    end

    def self.process_rubric_association_count(data)
      migration_ids = (data["rubrics"] || []).pluck("migration_id")
      rubrics = Rubric.where(migration_id: migration_ids)
      rubrics.each(&:update_association_count)
    end

    def self.track_metrics(migration)
      return unless migration.migration_settings[:is_copy_to]

      if migration.migration_settings[:associate_with_assignment_id].present?
        InstStatsd::Statsd.distributed_increment("content_migration.rubrics.associate_with_assignment")
      else
        InstStatsd::Statsd.distributed_increment("content_migration.rubrics.course_copy")
      end
    end
  end
end
