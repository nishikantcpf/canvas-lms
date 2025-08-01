# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
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
#

class Rubric < ActiveRecord::Base
  class RubricUniqueAlignments < ActiveModel::Validator
    def validate(record)
      return if record.criteria.nil?

      ids = record.criteria.pluck(:learning_outcome_id).compact

      record.errors.add :base, I18n.t("rubric.alignments.duplicated_outcome", "This rubric has Outcomes aligned more than once") if ids.uniq.count != ids.count
    end
  end

  class RubricAssessedAlignments < ActiveModel::Validator
    def validate(record)
      return if record.criteria.nil?

      ids = record.criteria.pluck(:learning_outcome_id).compact
      ids_from_results = record.learning_outcome_ids_from_results

      record.errors.add :base, I18n.t("This rubric removes criterions that have learning outcome results") unless (ids_from_results - ids).empty?
    end
  end

  include Workflow
  include HtmlTextHelper
  include Trackable

  POINTS_POSSIBLE_PRECISION = 4

  attr_writer :skip_updating_points_possible
  attr_accessor :is_duplicate, :is_manually_update

  belongs_to :user
  belongs_to :rubric # based on another rubric
  belongs_to :context, polymorphic: [:course, :account]
  has_many :rubric_associations, -> { where(workflow_state: "active") }, class_name: "RubricAssociation", inverse_of: :rubric, dependent: :destroy
  has_many :rubric_associations_with_deleted, class_name: "RubricAssociation", inverse_of: :rubric
  has_many :rubric_assessments, through: :rubric_associations, dependent: :destroy
  has_many :learning_outcome_alignments, -> { where("content_tags.tag_type='learning_outcome' AND content_tags.workflow_state<>'deleted'").preload(:learning_outcome) }, as: :content, inverse_of: :content, class_name: "ContentTag"
  has_many :learning_outcome_results, -> { active }, through: :rubric_assessments
  has_many :rubric_criteria, class_name: "RubricCriterion", inverse_of: :rubric, dependent: :destroy

  validates :context_id, :context_type, :workflow_state, presence: true
  validates :description, length: { maximum: maximum_text_length, allow_blank: true }
  validates :title, length: { maximum: maximum_string_length, allow_blank: false }
  validates :button_display, inclusion: { in: %w[numeric emoji letter] }
  validates :rating_order, inclusion: { in: %w[ascending descending] }

  validates_with RubricUniqueAlignments
  validates_with RubricAssessedAlignments

  before_validation :default_values
  before_save :set_default_hide_points
  before_create :set_root_account_id
  after_save :update_alignments
  after_save :touch_associations

  serialize :data
  simply_versioned

  scope :publicly_reusable, -> { where(reusable: true).order(best_unicode_collation_key("title")) }
  scope :matching, ->(search) { where(wildcard("rubrics.title", search)).order("rubrics.association_count DESC") }
  scope :before, ->(date) { where("rubrics.created_at<?", date) }
  scope :active, -> { where.not(workflow_state: %w[archived deleted draft]) }

  set_policy do
    given { |user, session| context.grants_right?(user, session, :manage_rubrics) }
    can :read and can :create and can :delete_associations

    given { |user, session| context.grants_right?(user, session, :manage_assignments_edit) }
    can :read and can :create and can :delete_associations

    given { |user, session| context.grants_right?(user, session, :manage) }
    can :read and can :create and can :delete_associations

    given { |user, session| context.grants_right?(user, session, :read_rubrics) }
    can :read

    # read_only means "associated with > 1 object for grading purposes"
    given { |user, session| !read_only && rubric_associations.for_grading.count < 2 && context.grants_right?(user, session, :manage_assignments_edit) }
    can :update and can :delete

    given { |user, session| !read_only && rubric_associations.for_grading.count < 2 && context.grants_right?(user, session, :manage_rubrics) }
    can :update and can :delete

    given { |user, session| context.grants_right?(user, session, :manage_assignments_edit) }
    can :delete

    given { |user, session| context.grants_right?(user, session, :manage_rubrics) }
    can :delete

    given { |user, session| context.grants_right?(user, session, :read) }
    can :read

    given { |user, session| context.grants_right?(user, session, :manage_rubrics) }
    can :archive

    given { |user, session| context.grants_right?(user, session, :manage_rubrics) }
    can :unarchive
  end

  workflow do
    state :active do
      event :archive, transitions_to: :archived
    end
    state :archived do
      event :unarchive, transitions_to: :active
    end
    state :draft
    state :deleted
  end

  def archive
    # overrides 'archive' event in workflow to make sure the feature flag is enabled
    # remove this and 'unarchive' method when feature flag is removed
    return unless enhanced_rubrics_enabled?

    InstStatsd::Statsd.distributed_increment("#{context.class.to_s.downcase}.rubrics.archived")
    super
  end

  def unarchive
    super if enhanced_rubrics_enabled?
  end

  def draft
    super if enhanced_rubrics_enabled?
  end

  def self.aligned_to_outcomes
    where(
      ContentTag.learning_outcome_alignments
        .active
        .where(content_type: "Rubric")
        .where("content_tags.content_id = rubrics.id")
        .arel.exists
    )
  end

  def self.with_at_most_one_association
    joins(<<~SQL.squish)
      LEFT JOIN #{RubricAssociation.quoted_table_name} associations_for_count
      ON rubrics.id = associations_for_count.rubric_id
      AND associations_for_count.purpose = 'grading'
      AND associations_for_count.workflow_state = 'active'
    SQL
      .group("rubrics.id")
      .having("COUNT(rubrics.id) < 2")
  end

  def self.unassessed
    joins(<<~SQL.squish)
      LEFT JOIN #{RubricAssociation.quoted_table_name} associations_for_unassessed
      ON rubrics.id = associations_for_unassessed.rubric_id
      AND associations_for_unassessed.purpose = 'grading'
      AND associations_for_unassessed.workflow_state = 'active'
    SQL
      .joins(<<~SQL.squish)
        LEFT JOIN #{RubricAssessment.quoted_table_name} assessments_for_unassessed
        ON associations_for_unassessed.id = assessments_for_unassessed.rubric_association_id
      SQL
      .where(assessments_for_unassessed: { id: nil })
  end

  def self.unassessed_and_with_at_most_one_association
    joins(<<~SQL.squish)
      LEFT JOIN #{RubricAssociation.quoted_table_name} associations_for_unassessed
      ON rubrics.id = associations_for_unassessed.rubric_id
      AND associations_for_unassessed.purpose = 'grading'
      AND associations_for_unassessed.workflow_state = 'active'
    SQL
      .where(<<~SQL.squish)
        NOT EXISTS(
          SELECT *
          FROM #{RubricAssessment.quoted_table_name} assessments_for_unassessed
          WHERE associations_for_unassessed.id = assessments_for_unassessed.rubric_association_id
        )
      SQL
      .group("rubrics.id")
      .having("COUNT(rubrics.id) < 2")
  end

  def default_values
    if Rails.env.test?
      populate_rubric_title # there are too many specs to change and i'm too lazy
    end

    cnt = 0
    siblings = Rubric.where(context_id:, context_type:).where("workflow_state<>'deleted'")
    siblings = siblings.where("id<>?", id) unless new_record?
    if title.present?
      original_title = title
      while siblings.where(title:).exists?
        cnt += 1
        self.title = "#{original_title} (#{cnt})"
      end
    end
    self.context_code = context_type && "#{context_type.underscore}_#{context_id}"
  end

  alias_method :destroy_permanently!, :destroy
  def destroy
    self.workflow_state = "deleted"
    if save
      rubric_associations.in_batches.destroy_all
      rubric_criteria.in_batches.destroy_all
      true
    end
  end

  def restore
    self.workflow_state = "active"
    if save
      rubric_associations_with_deleted.where(workflow_state: "deleted").find_each(&:restore)
      true
    end
  end

  # If any rubric_associations for a given context are marked as
  # bookmarked, then the rubric will show up in the context's list
  # of rubrics.  The two main values for the 'purpose' field on
  # a rubric_association are 'grading' and 'bookmark'.  Confusing,
  # I know.
  def destroy_for(context, current_user: nil)
    ras = rubric_associations.where(context_id: context, context_type: context.class.to_s)
    if context.instance_of?(Course)
      # if rubric is removed at the course level, we want to destroy any
      # assignment associations found in the context of the course
      ras.each do |association|
        association.updating_user = current_user
        association.destroy
      end
    else
      ras.destroy_all
    end

    if rubric_associations.bookmarked.none?
      destroy
    end
  end

  def update_alignments
    if alignments_need_update?
      outcome_ids = []
      unless deleted?
        outcome_ids = data_outcome_ids
      end
      LearningOutcome.update_alignments(self, context, outcome_ids)
    end
    true
  end

  def touch_associations
    if alignments_need_update?
      # associations might need to update their alignments also
      rubric_associations.bookmarked.each do |ra|
        ra.skip_updating_points_possible = @skip_updating_points_possible
        ra.save
      end
    end
  end

  def alignments_need_update?
    saved_change_to_data? || saved_change_to_workflow_state?
  end

  def data_outcome_ids
    (data || []).filter_map { |c| c[:learning_outcome_id] }.map(&:to_i).uniq
  end

  def outcome_friendly_descriptions
    OutcomeFriendlyDescription.where(learning_outcome_id: data_outcome_ids)
  end

  def outcome_data
    return [] unless data_outcome_ids.present?

    LearningOutcome.where(id: data_outcome_ids).map do |outcome|
      { id: outcome.id, display_name: outcome.display_name }
    end
  end

  def criteria_object
    reconstitute_criteria(data)
  end

  def criteria
    data
  end

  def associate_with(association, context, opts = {})
    if opts[:purpose] == "grading"
      res = rubric_associations.where(association_id: association, association_type: association.class.to_s, purpose: "grading").first
      return res if res
    elsif opts[:update_if_existing]
      res = rubric_associations.where(association_id: association, association_type: association.class.to_s).first
      return res if res
    end
    purpose = opts[:purpose] || "unknown"
    ra = rubric_associations.build(association_object: association,
                                   context:,
                                   use_for_grading: !!opts[:use_for_grading],
                                   purpose:)
    ra.skip_updating_points_possible = opts[:skip_updating_points_possible] || @skip_updating_points_possible
    ra.skip_updating_rubric_association_count = opts[:skip_updating_rubric_association_count]
    ra.updating_user = opts[:current_user]
    if ra.save && association.is_a?(Assignment)
      association.mark_downstream_changes(["rubric"])
    end
    ra.updating_user = nil
    ra
  end

  def update_with_association(current_user, rubric_params, context, association_params)
    self.free_form_criterion_comments = rubric_params[:free_form_criterion_comments] == "1" if rubric_params[:free_form_criterion_comments]
    self.user ||= current_user
    self.is_manually_update = association_params[:update_if_existing]
    rubric_params[:hide_score_total] ||= association_params[:hide_score_total]
    @skip_updating_points_possible = association_params[:skip_updating_points_possible]
    update_criteria(rubric_params, association_params[:association_object])

    return self unless valid?

    RubricAssociation.generate(current_user, self, context, association_params) if association_params[:association_object] || association_params[:url]
  end

  def unique_item_id(id = nil)
    @used_ids ||= {}
    while !id || @used_ids[id]
      id = "#{rubric_id || self.id}_#{rand(10_000)}"
    end
    @used_ids[id] = true
    id
  end

  def update_criteria(params, association_object = nil)
    if new_record?
      self.is_duplicate = ActiveModel::Type::Boolean.new.cast(params[:is_duplicate]) if params[:is_duplicate]
      without_versioning(&:save)
    end
    data = generate_criteria(params, association_object)
    self.hide_score_total = params[:hide_score_total] if hide_score_total.nil? || (association_count || 0) < 2
    self.data = data.criteria
    self.button_display = params[:button_display] if params.key?(:button_display)
    self.title = data.title
    self.points_possible = data.points_possible
    self.hide_points = params[:hide_points]
    self.rating_order = params[:rating_order] if params.key?(:rating_order)
    self.workflow_state = params[:workflow_state] if params[:workflow_state]
    self.is_duplicate = params[:is_duplicate] if params[:is_duplicate]
    save
    self
  end

  def update_mastery_scales(save = true)
    return unless context.root_account.feature_enabled?(:account_level_mastery_scales)

    mastery_scale = context.resolved_outcome_proficiency
    return if mastery_scale.nil?

    data.each do |criterion|
      update_criterion_from_mastery_scale(criterion, mastery_scale)
    end
    if data_changed?
      self.points_possible = total_points_from_criteria(data)
      save! if save
    end
  end

  def criterion_needs_update?(criterion, mastery_scale)
    return false if criterion[:learning_outcome_id].blank?

    return true if criterion[:points] != mastery_scale.points_possible
    return true if criterion[:mastery_points] != mastery_scale.mastery_points
    return true if criterion[:ratings]&.length != mastery_scale.outcome_proficiency_ratings.length

    criterion[:ratings].zip(mastery_scale.outcome_proficiency_ratings).any? do |criterion_rating, proficiency_rating|
      criterion_rating[:description] != proficiency_rating.description ||
        criterion_rating[:long_description] != "" ||
        criterion_rating[:points] != proficiency_rating.points
    end
  end

  def update_criterion_from_mastery_scale(criterion, mastery_scale)
    return unless criterion_needs_update?(criterion, mastery_scale)

    criterion[:points] = mastery_scale.points_possible
    criterion[:mastery_points] = mastery_scale.mastery_points
    criterion[:ratings] = mastery_scale.outcome_proficiency_ratings.map { |pr| criterion_rating(pr, criterion[:id]) }
  end

  def update_learning_outcome_criteria(outcome)
    data.each do |criterion|
      update_learning_outcome_criterion(criterion, outcome) if criterion[:learning_outcome_id] == outcome.id
    end
    if data_changed?
      self.points_possible = total_points_from_criteria(data)
      save!
    end
  end

  def update_learning_outcome_criterion(criterion, outcome)
    criterion[:description] = outcome.short_description
    criterion[:long_description] = outcome.description
    unless context.root_account.feature_enabled?(:account_level_mastery_scales)
      criterion[:points] = outcome.points_possible
      criterion[:mastery_points] = outcome.mastery_points
      criterion[:ratings] = outcome.rubric_criterion.nil? ? [] : generate_criterion_ratings(outcome, criterion[:id])
    end
  end

  def generate_criterion_ratings(outcome, criterion_id)
    outcome.rubric_criterion[:ratings].map do |rating|
      criterion_rating(rating, criterion_id)
    end
  end

  def criterion_rating(rating_data, criterion_id)
    {
      description: (rating_data[:description].presence || t("No Description")).strip,
      long_description: (rating_data[:long_description] || "").strip,
      points: rating_data[:points].to_f,
      criterion_id:,
      id: unique_item_id(rating_data[:id])
    }
  end

  def will_change_with_update?(params)
    params ||= {}
    return true if params[:free_form_criterion_comments] && !!free_form_criterion_comments != (params[:free_form_criterion_comments] == "1")

    data = generate_criteria(params)
    return true if data.title != title || data.points_possible != points_possible
    return true if Rubric.normalize(data.criteria) != Rubric.normalize(criteria)

    false
  end

  def populate_rubric_title
    self.title ||= context && t("context_name_rubric", "%{course_name} Rubric", course_name: context.name)
  end

  CriteriaData = Struct.new(:criteria, :points_possible, :title)
  Criterion = Struct.new(:description, :long_description, :points, :id, :criterion_use_range, :learning_outcome_id, :mastery_points, :ignore_for_scoring, :ratings, :title, :migration_id, :percentage, :order, keyword_init: true)
  Rating = Struct.new(:description, :long_description, :points, :id, :criterion_id, :migration_id, :percentage, keyword_init: true)
  # association_object is only needed for generating via llm
  def generate_criteria(params, association_object = nil)
    @used_ids = {}
    valid_bools = [true, "true", "1"]
    title = params[:title] || t("context_name_rubric", "%{course_name} Rubric", course_name: context.name)
    criteria = []
    if Canvas::Plugin.value_to_boolean(params[:criteria_via_llm]) && Rubric.ai_rubrics_enabled?(context)
      criteria = generate_criteria_via_llm(association_object)
    else
      (params[:criteria] || {}).each do |idx, criterion_data|
        criterion = {}
        criterion[:description] = (criterion_data[:description].presence || t("no_description", "No Description")).strip
        # Outcomes descriptions are already html sanitized, so use that if an outcome criteria
        # is present. Otherwise we need to sanitize the input ourselves.
        unless criterion_data[:learning_outcome_id].present?
          criterion[:long_description] = format_message((criterion_data[:long_description] || "").strip).first
        end
        criterion[:points] = criterion_data[:points].to_f
        criterion_data[:id] = criterion_data[:id].strip if criterion_data[:id]
        criterion_data[:id] = nil if criterion_data[:id] && criterion_data[:id].empty?
        criterion[:id] = unique_item_id(criterion_data[:id])
        criterion[:criterion_use_range] = [true, "true"].include?(criterion_data[:criterion_use_range])
        if criterion_data[:learning_outcome_id].present?
          outcome = LearningOutcome.where(id: criterion_data[:learning_outcome_id]).first
          criterion[:long_description] = outcome&.description || ""
          if outcome
            criterion[:learning_outcome_id] = outcome.id
            criterion[:mastery_points] = (criterion_data[:mastery_points] || outcome.data&.dig(:rubric_criterion, :mastery_points))&.to_f
            criterion[:ignore_for_scoring] = valid_bools.include?(criterion_data[:ignore_for_scoring])
          end
        end

        ratings = (criterion_data[:ratings] || {}).values.map do |rating_data|
          rating_data[:id] = rating_data[:id].strip if rating_data[:id]
          criterion_rating(rating_data, criterion[:id])
        end
        criterion[:ratings] = ratings.sort_by { |r| [-1 * (r[:points] || 0), r[:description] || CanvasSort::First] }
        criterion[:points] = criterion[:ratings].pluck(:points).max || 0

        # Record both the criterion data and the original ID that was passed in
        # (we'll use the ID when we sort the criteria below)
        criteria.push([idx, criterion])
      end
      criteria = criteria.sort_by { |criterion| criterion.first&.to_i || CanvasSort::First }
                         .map(&:second)
    end
    points_possible = total_points_from_criteria(criteria)&.round(POINTS_POSSIBLE_PRECISION)
    CriteriaData.new(criteria, points_possible, title)
  end

  DEFAULT_GENERATE_OPTIONS = {
    criteria_count: 5,
    rating_count: 4,
    points_per_criterion: 20,
    use_range: false,
    grade_level: "higher-ed"
  }.freeze
  def generate_criteria_via_llm(association_object, generate_options = {})
    unless association_object.is_a?(AbstractAssignment)
      raise "LLM generation is only available for rubrics associated with an Assignment"
    end

    unless user
      raise "User must be associated to rubric before LLM generation"
    end

    llm_config = LLMConfigs.config_for("rubric_create")
    if llm_config.nil?
      raise "No LLM config found for rubric creation"
    end

    assignment = association_object
    dynamic_content = {
      CONTENT: {
        id: assignment.id,
        title: assignment.title,
        description: assignment.description,
        grading_type: assignment.grading_type,
        submission_types: assignment.submission_types,
      }.to_json,
      CRITERIA_COUNT: generate_options[:criteria_count] || DEFAULT_GENERATE_OPTIONS[:criteria_count],
      RATING_COUNT: generate_options[:rating_count] || DEFAULT_GENERATE_OPTIONS[:rating_count],
      ADDITIONAL_PROMPT_INFO: generate_options[:additional_prompt_info].present? ? "Also consider: #{generate_options[:additional_prompt_info]}" : "",
      GRADE_LEVEL: generate_options[:grade_level] || DEFAULT_GENERATE_OPTIONS[:grade_level],
    }

    prompt, options = llm_config.generate_prompt_and_options(substitutions: dynamic_content)

    response = nil
    time = Benchmark.measure do
      InstLLMHelper.with_rate_limit(user:, llm_config:) do
        response = InstLLMHelper.client(llm_config.model_id).chat(
          [{ role: "user", content: prompt }],
          **options.symbolize_keys
        )
      end
    end

    LLMResponse.create!(
      associated_assignment: association_object,
      user:,
      prompt_name: llm_config.name,
      prompt_model_id: llm_config.model_id,
      prompt_dynamic_content: dynamic_content,
      raw_response: response.message[:content],
      input_tokens: response.usage[:input_tokens],
      output_tokens: response.usage[:output_tokens],
      response_time: time.real.round(2),
      root_account_id: association_object.root_account_id
    )

    ai_rubric = JSON.parse(response.message[:content], symbolize_names: true)

    criteria = []
    ai_rubric[:criteria].each do |criterion_data|
      criterion = {}
      criterion[:id] = unique_item_id
      criterion[:description] = (criterion_data[:name].presence || t("no_description", "No Description")).strip
      criterion[:long_description] = criterion_data[:description].presence

      points = (generate_options[:points_per_criterion] || DEFAULT_GENERATE_OPTIONS[:points_per_criterion]).to_f
      points_decrement = points / [(criterion_data[:ratings].length - 1), 1].max
      ratings = criterion_data[:ratings].each_with_index.map do |rating_data, index|
        {
          description: (rating_data[:title].presence || t("no_description", "No Description")).strip,
          long_description: rating_data[:description].presence,
          points: (points - (points_decrement * index)).round,
          criterion_id: criterion[:id],
          id: unique_item_id
        }
      end
      criterion[:ratings] = ratings.sort_by { |r| [-1 * (r[:points] || 0), r[:description] || CanvasSort::First] }
      criterion[:points] = criterion[:ratings].pluck(:points).max || 0
      criterion[:criterion_use_range] = !!generate_options[:use_range]

      criteria.push(criterion)
    end
    criteria
  end

  def self.process_generate_criteria_via_llm(progress, course, user, association_object, generate_options)
    rubric = course.rubrics.build(user:)
    if rubric.grants_right?(user, :update)
      criteria = rubric.generate_criteria_via_llm(association_object, generate_options)
      progress.set_results({ criteria: })
      progress.complete!
    end
  rescue InstLLM::ServiceQuotaExceededError, InstLLM::ThrottlingError
    progress.set_results({ error: t("There was an error with generation capacity. Please try again later.") })
    progress.fail!
  rescue InstLLMHelper::RateLimitExceededError
    progress.set_results({ error: t("You have made too many criteria generation requests. Please try again later.") })
    progress.fail!
  rescue
    progress.set_results({ error: t("There was an error with the criteria generation. Please try agian later.") })
    progress.fail!
    raise
  end

  def reconstitute_criteria(criteria)
    criteria.map do |criterion|
      ratings = criterion[:ratings].map { |rating| Rating.new(**rating.slice(*Rating.members)) }
      Criterion.new(**criterion.slice(*Criterion.members), ratings:)
    end
  end

  def total_points_from_criteria(criteria)
    criteria.reject { |c| c[:ignore_for_scoring] }.pluck(:points).compact.sum
  end

  def reconcile_criteria_models(current_user)
    return unless enhanced_rubrics_enabled?

    return unless criteria.present? && criteria.is_a?(Array)

    criteria.each.with_index(1) do |old_school_criterion, index|
      criterion = rubric_criteria.find_by(order: index)
      if criterion
        update_params = { description: old_school_criterion[:description],
                          long_description: old_school_criterion[:long_description],
                          points: old_school_criterion[:points],
                          learning_outcome_id: old_school_criterion[:learning_outcome_id],
                          mastery_points: old_school_criterion[:mastery_points],
                          ignore_for_scoring: !!old_school_criterion[:ignore_for_scoring],
                          criterion_use_range: !!old_school_criterion[:criterion_use_range] }

        update_params[:created_by] = current_user if criterion.will_change_with_update(update_params)
        criterion.update!(update_params)
      else
        rubric_criteria.create!(description: old_school_criterion[:description],
                                long_description: old_school_criterion[:long_description],
                                points: old_school_criterion[:points],
                                order: index,
                                learning_outcome_id: old_school_criterion[:learning_outcome_id],
                                mastery_points: old_school_criterion[:mastery_points],
                                ignore_for_scoring: !!old_school_criterion[:ignore_for_scoring],
                                criterion_use_range: !!old_school_criterion[:criterion_use_range],
                                root_account_id:,
                                created_by: current_user)
      end
    end
    rubric_criteria.where("rubric_criteria.order > ?", criteria.length).delete_all
  end

  # undo innocuous changes introduced by migrations which break `will_change_with_update?`
  def self.normalize(criteria)
    case criteria
    when Array
      criteria.map { |criterion| Rubric.normalize(criterion) }
    when Hash
      h = criteria.compact_blank.stringify_keys
      h.delete("title") if h["title"] == h["description"]
      h.each do |k, v|
        h[k] = Rubric.normalize(v) if v.is_a?(Hash) || v.is_a?(Array)
      end
      h
    else
      criteria
    end
  end

  def set_root_account_id
    self.root_account_id ||=
      if context_type == "Account" && context.root_account?
        context.id
      else
        context&.root_account_id
      end
  end

  def set_default_hide_points
    self.hide_points = false if hide_points.nil?
  end

  def enhanced_rubrics_enabled?
    context.feature_enabled?(:enhanced_rubrics)
  end

  def learning_outcome_ids_from_results
    learning_outcome_results.select(:learning_outcome_id).distinct.pluck(:learning_outcome_id)
  end

  def rubric_assignment_associations?
    rubric_associations.where(association_type: "Assignment", workflow_state: "active").any?
  end

  def used_locations
    associations = rubric_associations.active.where(association_type: "Assignment")

    Assignment.where(id: associations.pluck(:association_id))
  end

  def update_association_count
    cnt = rubric_associations.for_grading.count
    with_versioning(true) do
      self.read_only = cnt > 1
      self.association_count = cnt
      save!
      destroy if cnt == 0 && rubric_associations.none? && !public
    end
  end

  def self.enhanced_rubrics_assignments_enabled?(context_to_check)
    Account.site_admin.feature_enabled?(:enhanced_rubrics_assignments) && context_to_check.feature_enabled?(:enhanced_rubrics)
  end

  def self.rubric_assessment_import_export_enabled?(context_to_check)
    Account.site_admin.feature_enabled?(:rubric_assessment_imports_exports) && context_to_check.feature_enabled?(:enhanced_rubrics)
  end

  def self.rubric_self_assessment_enabled?(context_to_check)
    return false if context_to_check.is_a?(Course) && !context_to_check.feature_enabled?(:assignments_2_student)

    context_to_check.feature_enabled?(:enhanced_rubrics) && context_to_check.root_account.feature_enabled?(:rubric_self_assessment)
  end

  def self.ai_rubrics_enabled?(context_to_check)
    return false unless context_to_check.is_a?(Course)

    context_to_check.feature_enabled?(:enhanced_rubrics) && context_to_check.feature_enabled?(:ai_rubrics)
  end
end
