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

describe DiscussionTopic do
  before :once do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true)
  end

  def create_enrolled_user(course, section, opts)
    opts.reverse_merge!(active_all: true, section:, enrollment_state: "active")
    user = user_factory(opts)
    user.save!
    course.enroll_user(user, opts[:enrollment_type], opts)
    user
  end

  def add_section_to_topic(topic, section, opts = {})
    opts.reverse_merge!({
                          workflow_state: "active"
                        })
    topic.sections_changed = true
    topic.is_section_specific = true
    topic.discussion_topic_section_visibilities <<
      DiscussionTopicSectionVisibility.new(
        discussion_topic: topic,
        course_section: section,
        workflow_state: opts[:workflow_state]
      )
  end

  describe ".create_graded_topic!" do
    it "returns a discussion topic with an attached assignment" do
      topic = DiscussionTopic.create_graded_topic!(course: @course, title: "My Graded Topic")
      aggregate_failures do
        expect(topic).to be_a DiscussionTopic
        expect(topic.assignment.submission_types).to eq "discussion_topic"
        expect(topic.graded?).to be true
      end
    end

    it "sets the title on both the assignment and discussion topic" do
      title = "My Graded Topic"
      topic = DiscussionTopic.create_graded_topic!(course: @course, title:)
      aggregate_failures do
        expect(topic.title).to eq title
        expect(topic.assignment.title).to eq title
      end
    end

    it "optionally accepts a user to be assigned to the discussion topic" do
      topic = DiscussionTopic.create_graded_topic!(course: @course, title: "My Graded Topic", user: @teacher)
      expect(topic.user).to eq @teacher
    end

    it "raises an error when the assignment is invalid" do
      expect { DiscussionTopic.create_graded_topic!(course: nil, title: "My Graded Topic") }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe ".preload_subentry_counts" do
    it "preloads the discussion subentry count" do
      topic1 = @course.discussion_topics.create!
      topic1.discussion_entries.create!(user: @teacher)
      topic2 = @course.discussion_topics.create!

      DiscussionTopic.preload_subentry_counts([topic1, topic2])
      aggregate_failures do
        expect(topic1.instance_variable_get(:@preloaded_subentry_count)).to eq 1
        expect(topic1.discussion_subentry_count).to eq 1
        expect(topic2.instance_variable_get(:@preloaded_subentry_count)).to eq 0
        expect(topic2.discussion_subentry_count).to eq 0
      end
    end
  end

  describe "#grading_standard_or_default" do
    context "when the DiscussionTopic belongs to a Course" do
      before(:once) do
        @assignment = @course.assignments.create(title: "discussion assignment", points_possible: 20)
        @topic = @course.discussion_topics.create!(assignment: @assignment)
        @grading_standard = grading_standard_for(@course)
      end

      it "returns the grading scheme used by the discussion topic, if one exists" do
        @assignment.update!(grading_standard: @grading_standard)
        expect(@topic.grading_standard_or_default).to be @grading_standard
      end

      it "returns the specific grading scheme used by the course over the default course grading scheme if no grading scheme is set for the assignment" do
        @course_gs = @course.grading_standards.create! standard_data: {
          a: { name: "Happy", value: 100 },
          b: { name: "Sad", value: 0 },
        }
        @course.update!(grading_standard: @grading_standard)
        @course.update_attribute :grading_standard, @course_gs
        expect(@topic.grading_standard_or_default).to be @course_gs
      end

      it "returns the grading scheme used by the topic if the topic and course are using a grading scheme" do
        @assignment.update!(grading_standard: @grading_standard)
        course_standard = grading_standard_for(@course, title: "new scheme")
        @course.update!(grading_standard: course_standard)
        expect(@topic.grading_standard_or_default).to be @grading_standard
      end

      it "returns the Canvas default grading scheme if neither the topic nor course are not using a grading scheme" do
        expect(@course.grading_standard_or_default.data).to eq GradingStandard.default_grading_standard
      end
    end

    context "when the DiscussionTopic belongs to a Group" do
      before(:once) do
        @group = @course.groups.create!
        @topic = @group.discussion_topics.create!
        @grading_standard = grading_standard_for(@course)
      end

      it "returns the group for the address_book_context" do
        expect(@topic.address_book_context_for(double)).to be @group
      end

      it "returns the grading scheme used by the course, if one exists" do
        @course.update!(grading_standard: @grading_standard)
        expect(@topic.grading_standard_or_default).to be @grading_standard
      end

      it "returns the Canvas default grading scheme if neither the topic nor course are not using a grading scheme" do
        expect(@topic.grading_standard_or_default.data).to eq GradingStandard.default_grading_standard
      end

      it "returns the Canvas default grading scheme if the Group belongs to an Account" do
        group = @course.root_account.groups.create!
        @topic.update!(context: group)
        expect(@topic.grading_standard_or_default.data).to eq GradingStandard.default_grading_standard
      end
    end
  end

  describe "default values for boolean attributes" do
    before(:once) do
      @topic = @course.discussion_topics.create!
    end

    let(:values) do
      DiscussionTopic.where(id: @topic).pick(
        :could_be_locked,
        :podcast_enabled,
        :podcast_has_student_posts,
        :require_initial_post,
        :pinned,
        :locked,
        :allow_rating,
        :only_graders_can_rate,
        :sort_by_rating
      )
    end

    it "saves boolean attributes as false if they are set to nil" do
      @topic.update!(
        could_be_locked: nil,
        podcast_enabled: nil,
        podcast_has_student_posts: nil,
        require_initial_post: nil,
        pinned: nil,
        locked: nil,
        allow_rating: nil,
        only_graders_can_rate: nil,
        sort_by_rating: nil
      )

      expect(values).to eq([false] * values.length)
    end

    it "saves boolean attributes as false if they are set to false" do
      @topic.update!(
        could_be_locked: false,
        podcast_enabled: false,
        podcast_has_student_posts: false,
        require_initial_post: false,
        pinned: false,
        locked: false,
        allow_rating: false,
        only_graders_can_rate: false,
        sort_by_rating: false
      )

      expect(values).to eq([false] * values.length)
    end

    it "saves boolean attributes as true if they are set to true" do
      @topic.update!(
        could_be_locked: true,
        podcast_enabled: true,
        podcast_has_student_posts: true,
        require_initial_post: true,
        pinned: true,
        locked: true,
        allow_rating: true,
        only_graders_can_rate: true,
        sort_by_rating: true
      )

      expect(values).to eq([true] * values.length)
    end
  end

  describe "default values" do
    subject(:discussion_topic) { @course.discussion_topics.create!(title:) }

    let(:default_title) { I18n.t("#discussion_topic.default_title", "No Title") }

    context "when the title is an empty string" do
      let(:title) { "" }

      it "sets its default value" do
        expect(discussion_topic.title).to eq(default_title)
      end
    end

    context "when the title is nil" do
      let(:title) { nil }

      it "sets its default value" do
        expect(discussion_topic.title).to eq(default_title)
      end
    end

    it "set sort order default" do
      d = DiscussionTopic.new
      expect(d.sort_order).to eq DiscussionTopic::SortOrder::DEFAULT
    end
  end

  it "santizes message" do
    @course.discussion_topics.create!(message: "<a href='#' onclick='alert(12);'>only this should stay</a>")
    expect(@course.discussion_topics.first.message).to eql("<a href=\"#\">only this should stay</a>")
  end

  it "side-comment discussion type is threaded when it has threaded replies" do
    topic = @course.discussion_topics.create!(message: "test")
    topic.discussion_type = "side_comment"
    entry = topic.discussion_entries.create!(message: "test")
    entry.reply_from(user: @student, html: "reply 1")
    expect(topic.threaded?).to be true
  end

  it "side-comment discussion type is not threaded when it does not have threaded replies" do
    topic = @course.discussion_topics.create!(message: "test")
    topic.discussion_type = "side_comment"
    topic.discussion_entries.create!(message: "test")
    expect(topic.threaded?).to be false
  end

  it "defaults to not_threaded type" do
    d = DiscussionTopic.new
    expect(d.discussion_type).to eq "not_threaded"

    d.threaded = "1"
    expect(d.discussion_type).to eq "threaded"

    d.threaded = ""
    expect(d.discussion_type).to eq "not_threaded"
  end

  it "defaults to threaded type with react_discussions_post" do
    @course.enable_feature!("react_discussions_post")
    topic = @course.discussion_topics.create!(message: "test")
    expect(topic.discussion_type).to eq "threaded"
  end

  it "parent topic is threaded when children has threaded replies" do
    group_discussion_assignment
    @topic.refresh_subtopics
    subtopic = @topic.child_topics.first
    entry = subtopic.discussion_entries.create!(message: "test")
    @course.groups.first.add_user(@student)

    entry.reply_from(user: @student, html: "reply 1")
    expect(@topic.threaded?).to be true
  end

  it "requires a valid discussion_type" do
    @topic = @course.discussion_topics.build(message: "test", discussion_type: "gesundheit")
    expect(@topic.save).to be false
    expect(@topic.errors.attribute_names).to eq [:discussion_type]
  end

  it "updates the assignment it is associated with" do
    a = @course.assignments.create!(title: "some assignment", points_possible: 5)
    expect(a.points_possible).to be(5.0)
    expect(a.submission_types).not_to eql("online_quiz")
    t = @course.discussion_topics.build(assignment: a, title: "some topic", message: "a little bit of content")
    t.save
    expect(t.assignment_id).to eql(a.id)
    expect(t.assignment).to eql(a)
    a.reload
    expect(a.discussion_topic).to eql(t)
    expect(a.submission_types).to eql("discussion_topic")
  end

  it "deletes the assignment if the topic is no longer graded" do
    a = @course.assignments.create!(title: "some assignment", points_possible: 5)
    expect(a.points_possible).to be(5.0)
    expect(a.submission_types).not_to eql("online_quiz")
    t = @course.discussion_topics.build(assignment: a, title: "some topic", message: "a little bit of content")
    t.save
    expect(t.assignment_id).to eql(a.id)
    expect(t.assignment).to eql(a)
    a.reload
    expect(a.discussion_topic).to eql(t)
    t.assignment = nil
    t.save
    t.reload
    expect(t.assignment_id).to be_nil
    expect(t.assignment).to be_nil
    a.reload
    expect(a).to be_deleted
    expect(t.graded?).to be false
  end

  context "permissions" do
    before do
      @course.enable_feature!(:react_discussions_post)
      @course.root_account.enable_feature!(:discussion_create)
      @teacher1 = @teacher
      @teacher2 = user_factory
      teacher_in_course(course: @course, user: @teacher2, active_all: true)

      @topic = @course.discussion_topics.create!(user: @teacher1)
      @topic.unpublish!
      @topic.discussion_type = "threaded"
      @entry = @topic.discussion_entries.create!(user: @teacher1)
      @entry.discussion_topic = @topic

      @relevant_permissions = %i[read reply update delete]
    end

    it "does grant create permission with create_forum but no moderate_forum" do
      @course.account.role_overrides.create!(role: teacher_role, permission: "moderate_forum", enabled: false)
      expect(@topic.reload.check_policy(@teacher2)).to eql %i[read read_replies reply create duplicate attach student_reporting create_assign_to]
    end

    it "does grant create permission with moderate_forum but no create_forum" do
      @course.account.role_overrides.create!(role: teacher_role, permission: "create_forum", enabled: false)
      expect(@topic.reload.check_policy(@teacher2)).to eql %i[read read_replies reply update delete create duplicate attach student_reporting read_as_admin moderate_forum manage_assign_to]
    end

    it "does not grant create permission without moderate_forum and create_forum" do
      @course.account.role_overrides.create!(role: teacher_role, permission: "create_forum", enabled: false)
      @course.account.role_overrides.create!(role: teacher_role, permission: "moderate_forum", enabled: false)
      expect(@topic.reload.check_policy(@teacher2)).to eql %i[read read_replies reply attach student_reporting]
    end

    it "does not grant moderate permissions without read permissions" do
      @course.account.role_overrides.create!(role: teacher_role, permission: "read_forum", enabled: false)
      expect(@topic.reload.check_policy(@teacher2)).to eql %i[create duplicate attach student_reporting manage_assign_to create_assign_to]
    end

    it "grants permissions if it not locked" do
      @topic.publish!
      expect((@topic.check_policy(@teacher1) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@topic.check_policy(@teacher2) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@topic.check_policy(@student) & @relevant_permissions).map(&:to_s).sort).to eq ["read", "reply"].sort

      expect((@entry.check_policy(@teacher1) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@entry.check_policy(@teacher2) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@entry.check_policy(@student) & @relevant_permissions).map(&:to_s).sort).to eq ["read", "reply"].sort
    end

    it "does not grant reply permissions to students if it is locked" do
      @topic.publish!
      @topic.lock!
      expect((@topic.check_policy(@teacher1) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@topic.check_policy(@teacher2) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@topic.check_policy(@student) & @relevant_permissions).map(&:to_s)).to eq ["read"]

      expect((@entry.check_policy(@teacher1) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@entry.check_policy(@teacher2) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@entry.check_policy(@student) & @relevant_permissions).map(&:to_s)).to eq ["read"]
    end

    it "does not grant any permissions to students if it is unpublished" do
      expect((@topic.check_policy(@teacher1) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@topic.check_policy(@teacher2) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@topic.check_policy(@student) & @relevant_permissions).map(&:to_s).sort).to eq []

      expect((@entry.check_policy(@teacher1) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@entry.check_policy(@teacher2) & @relevant_permissions).map(&:to_s).sort).to eq %w[read reply update delete].sort
      expect((@entry.check_policy(@student) & @relevant_permissions).map(&:to_s).sort).to eq []
    end

    describe "manage_assign_to" do
      context "graded topics" do
        before do
          @topic.assignment = @course.assignments.create!(title: "some assignment", points_possible: 5)
          @topic.save!
        end

        it "is granted to users with moderate_forum and manage_assignments_edit permission" do
          expect(@topic.grants_right?(@teacher1, :manage_assign_to)).to be true
        end

        it "is not granted to users with moderate_forum and not manage_assignments_edit permission" do
          RoleOverride.create!(context: @course.account, permission: "manage_assignments_edit", role: teacher_role, enabled: false)
          expect(@topic.grants_right?(@teacher1, :manage_assign_to)).to be false
        end

        it "is not granted to users with manage_assignments_edit and not moderate_forum permission" do
          RoleOverride.create!(context: @course.account, permission: "moderate_forum", role: teacher_role, enabled: false)
          expect(@topic.grants_right?(@teacher1, :manage_assign_to)).to be false
        end
      end

      context "ungraded topics" do
        it "is granted to teachers with moderate_forum permission" do
          expect(@topic.grants_right?(@teacher1, :manage_assign_to)).to be true
        end

        it "is not granted to students by default" do
          expect(@topic.grants_right?(@student, :manage_assign_to)).to be false
        end

        it "is granted to students with moderate_forum permission and an unrestricted enrollment" do
          RoleOverride.create!(context: @course.account, permission: "moderate_forum", role: student_role, enabled: true)
          expect(@topic.grants_right?(@student, :manage_assign_to)).to be true
        end

        it "is not granted to students with moderate_forum permission and a restricted enrollment" do
          RoleOverride.create!(context: @course.account, permission: "moderate_forum", role: student_role, enabled: true)
          @student.enrollments.where(course: @course).first.update!(limit_privileges_to_course_section: true)
          expect(@topic.grants_right?(@student, :manage_assign_to)).to be false
        end

        it "is granted to account admins" do
          account_admin = account_admin_user(account: @course.root_account)
          expect(@topic.grants_right?(account_admin, :manage_assign_to)).to be true
        end
      end
    end
  end

  describe "visibility" do
    before(:once) do
      @topic = @course.discussion_topics.create!(user: @teacher)
    end

    it "is visible to author when unpublished" do
      @topic.unpublish!
      expect(@topic.visible_for?(@teacher)).to be_truthy
    end

    it "returns the course for the address_book_context" do
      expect(@topic.address_book_context_for(double)).to be @course
    end

    it "is visible when published even when for delayed posting" do
      @topic.delayed_post_at = 5.days.from_now
      @topic.workflow_state = "post_delayed"
      @topic.save!
      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "is not visible when unpublished even when it is active" do
      @topic.unpublish!
      expect(@topic.visible_for?(@student)).to be_falsey
    end

    it "is visible to students when topic is not locked" do
      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "clears the context modules cache on section change" do
      context_module = @course.context_modules.create!(name: "some module")
      context_module.add_item(type: "discussion_topic", id: @topic.id)
      context_module.updated_at = 1.day.ago
      context_module.save!
      last_updated_at = context_module.updated_at
      add_section_to_topic(@topic, @course.course_sections.create!)
      @topic.save!
      context_module.reload
      expect(last_updated_at).not_to eq context_module.updated_at
    end

    it "is visible to students when topic delayed_post_at is in the future" do
      @topic.delayed_post_at = 5.days.from_now
      @topic.save!
      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "is visible to students when topic is for delayed posting" do
      @topic.workflow_state = "post_delayed"
      @topic.save!
      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "is visible to students when topic delayed_post_at is in the past" do
      @topic.delayed_post_at = 5.days.ago
      @topic.save!
      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "is visible to students when topic delayed_post_at is nil" do
      @topic.delayed_post_at = nil
      @topic.save!
      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "is not visible to unauthenticated users in a public course" do
      @course.update_attribute(:is_public, true)
      expect(@topic.visible_for?(nil)).to be_falsey
    end

    it "is visible when no delayed_post but assignment unlock date in future" do
      @topic.delayed_post_at = nil
      group_category = @course.group_categories.create(name: "category")
      @topic.group_category = group_category
      @topic.assignment = @course.assignments.build(submission_types: "discussion_topic",
                                                    title: @topic.title,
                                                    unlock_at: 10.days.from_now,
                                                    lock_at: 30.days.from_now)
      @topic.assignment.infer_times
      @topic.assignment.saved_by = :discussion_topic
      @topic.save

      expect(@topic.visible_for?(@student)).to be_truthy
    end

    it "is visible to teachers not locked to a section in the course" do
      @topic.update_attribute(:delayed_post_at, 1.day.from_now)
      new_teacher = user_factory
      @course.enroll_teacher(new_teacher).accept!
      expect(@topic.visible_for?(new_teacher)).to be_truthy
    end

    it "is not visible to teachers locked to a different section in a course" do
      section1 = @course.course_sections.create!(name: "Section 1")
      section2 = @course.course_sections.create!(name: "Section 2")
      new_teacher = user_factory
      @course.enroll_teacher(new_teacher, section: section1, allow_multiple_enrollments: true).accept!
      Enrollment.limit_privileges_to_course_section!(@course, new_teacher, true)
      ann = @course.announcements.create!(message: "testing", is_section_specific: true, course_sections: [section2])
      ann.save!
      expect(ann.visible_for?(new_teacher)).not_to be_truthy
    end

    it "is visible to teachers locked to the same section in a course" do
      section1 = @course.course_sections.create!(name: "Section 1")
      @course.course_sections.create!(name: "Section 2")
      new_teacher = user_factory
      @course.enroll_teacher(new_teacher, section: section1, allow_multiple_enrollments: true).accept!
      Enrollment.limit_privileges_to_course_section!(@course, new_teacher, true)
      ann = @course.announcements.create!(message: "testing", is_section_specific: true, course_sections: [section1])
      ann.save!
      expect(ann.visible_for?(new_teacher)).to be_truthy
    end

    it "unpublished topics should not be visible to custom account admins by default" do
      @topic.unpublish

      account = @course.root_account
      nobody_role = custom_account_role("NobodyAdmin", account:)
      admin = account_admin_user(account:, role: nobody_role, active_user: true)
      expect(@topic.visible_for?(admin)).to be_falsey
    end

    it "unpublished topics should be visible to account admins with :read_course_content permission" do
      @topic.unpublish

      account = @course.root_account
      nobody_role = custom_account_role("NobodyAdmin", account:)
      account_with_role_changes(account:, role: nobody_role, role_changes: { read_course_content: true, read_forum: true })
      admin = account_admin_user(account:, role: nobody_role, active_user: true)
      expect(@topic.visible_for?(admin)).to be_truthy
    end

    it "section-specific-topics should be visible to account admins" do
      account = @course.root_account
      section = @course.course_sections.create!(name: "Section of topic")
      add_section_to_topic(@topic, section)
      @topic.save!
      nobody_role = custom_account_role("NobodyAdmin", account:)
      account_with_role_changes(account:,
                                role: nobody_role,
                                role_changes: { read_course_content: true, read_forum: true })
      admin = account_admin_user(account:, role: nobody_role, active_user: true)
      expect(@topic.visible_for?(admin)).to be_truthy
    end

    context "participants with teachers and tas" do
      before(:once) do
        group_course = course_factory(active_course: true)
        @group_student, @group_ta, @group_teacher = create_users(3, return_type: :record)
        @not_group_student, @group_designer = create_users(2, return_type: :record)
        group_course.enroll_teacher(@group_teacher).accept!
        group_course.enroll_ta(@group_ta).accept!
        group_course.enroll_designer(@group_designer).accept!
        group_category = group_course.group_categories.create(name: "new cat")
        group = group_course.groups.create(name: "group", group_category:)
        group.add_user(@group_student)
        @announcement = group.announcements.build(title: "group topic", message: "group message")
        @announcement.save!
      end

      it "is visible to instructors and tas" do
        [@group_student, @group_ta, @group_teacher].each do |user|
          expect(@announcement.active_participants_include_tas_and_teachers.include?(user)).to be_truthy
        end
      end

      it "does not include people out of the group or non-instructors" do
        [@not_group_student, @group_designer].each do |user|
          expect(@announcement.active_participants_include_tas_and_teachers.include?(user)).to be_falsey
        end
      end

      describe "differentiated modules" do
        context "ungraded discussions" do
          before do
            @topic = discussion_topic_model(user: @teacher, context: @course)
            @topic.update!(only_visible_to_overrides: true)
            @course_section = @course.course_sections.create
            @student1 = student_in_course(course: @course, active_enrollment: true).user
            @student2 = student_in_course(course: @course, active_enrollment: true, section: @course_section).user
            @teacher1 = teacher_in_course(course: @course, active_enrollment: true).user
            @teacher2_limited_to_section = teacher_in_course(course: @course, active_enrollment: true).user
            Enrollment.limit_privileges_to_course_section!(@course, @teacher2_limited_to_section, true)
          end

          it "is visible only to the assigned student" do
            override = @topic.assignment_overrides.create!
            override.assignment_override_students.create!(user: @student1)
            expect(@topic.visible_for?(@student1)).to be_truthy
            expect(@topic.visible_for?(@student2)).to be_falsey

            expect(@topic.visible_for?(@teacher1)).to be_truthy
            expect(@topic.visible_for?(@teacher2_limited_to_section)).to be_truthy
          end

          it "is visible only to users who can access the assigned section" do
            @topic.assignment_overrides.create!(set: @course_section)
            expect(@topic.visible_for?(@student1)).to be_falsey
            expect(@topic.visible_for?(@student2)).to be_truthy

            expect(@topic.visible_for?(@teacher1)).to be_truthy
            expect(@topic.visible_for?(@teacher2_limited_to_section)).to be_falsey
          end

          it "is visible only to students in module override section" do
            context_module = @course.context_modules.create!(name: "module")
            context_module.content_tags.create!(content: @topic, context: @course)

            override2 = @topic.assignment_overrides.create!(unlock_at: "2022-02-01T01:00:00Z",
                                                            unlock_at_overridden: true,
                                                            lock_at: "2022-02-02T01:00:00Z",
                                                            lock_at_overridden: true)
            override2.assignment_override_students.create!(user: @student1)

            expect(@topic.visible_for?(@student1)).to be_truthy
            expect(@topic.visible_for?(@student2)).to be_falsey

            expect(@topic.visible_for?(@teacher1)).to be_truthy
            expect(@topic.visible_for?(@teacher2_limited_to_section)).to be_truthy
          end

          it "is visible to teachers with section limited access" do
            account_admin = account_admin_user(account: @course.root_account)
            @course.enroll_teacher(@teacher2_limited_to_section, section: @course_section, allow_multiple_enrollments: true).accept!
            Enrollment.limit_privileges_to_course_section!(@course, @teacher2_limited_to_section, true)
            @topic = discussion_topic_model(user: account_admin, context: @course)
            @topic.update!(only_visible_to_overrides: true)
            @topic.assignment_overrides.create!(set: @course_section)

            expect(@topic.visible_for?(@teacher2_limited_to_section)).to be_truthy
          end
        end
      end
    end

    context "differentiated assignements" do
      before do
        @course = course_factory(active_course: true)
        discussion_topic_model(user: @teacher, context: @course)
        @course.enroll_teacher(@teacher).accept!
        @course_section = @course.course_sections.create
        @student1, @student2, @student3 = create_users(3, return_type: :record)

        @assignment = @course.assignments.create!(title: "some discussion assignment", only_visible_to_overrides: true)
        @assignment.submission_types = "discussion_topic"
        @assignment.save!
        @topic.assignment_id = @assignment.id
        @topic.save!

        @course.enroll_student(@student2, enrollment_state: "active")
        @section = @course.course_sections.create!(name: "test section")
        student_in_section(@section, user: @student1)
        create_section_override_for_assignment(@assignment, { course_section: @section })
        @course.reload
      end

      it "is visible to a student with an override" do
        expect(@topic.visible_for?(@student1)).to be_truthy
      end

      it "is not visible to a student without an override" do
        expect(@topic.visible_for?(@student2)).to be_falsey
      end

      it "is visible to a teacher" do
        expect(@topic.visible_for?(@teacher)).to be_truthy
      end

      it "does not grant reply permissions to a student without an override" do
        expect(@topic.check_policy(@student1)).to include :reply
        expect(@topic.check_policy(@student2)).not_to include :reply
      end

      context "active_participants_with_visibility" do
        it "filters participants by visibility" do
          [@student1, @teacher].each do |user|
            expect(@topic.active_participants_with_visibility.include?(user)).to be_truthy
          end
          expect(@topic.active_participants_with_visibility.include?(@student2)).to be_falsey
        end

        it "works when ungraded and context is a course" do
          @course.group_categories.create(name: "new cat")
          @topic = @course.discussion_topics.create(title: "group topic")
          @topic.save!

          expect(@topic.context).to eq(@course)
          expect(@topic.active_participants_with_visibility.include?(@student1)).to be_truthy
          expect(@topic.active_participants_with_visibility.include?(@student2)).to be_truthy
        end

        it "filters out-of-section students" do
          topic = @course.discussion_topics.create(
            title: "foo", message: "bar", user: @teacher
          )
          section1 = @course.course_sections.create!
          section2 = @course.course_sections.create!
          student1 = create_enrolled_user(@course, section1, name: "student 1", enrollment_type: "StudentEnrollment")
          student2 = create_enrolled_user(@course, section2, name: "student 2", enrollment_type: "StudentEnrollment")
          @course.reload
          add_section_to_topic(topic, section2)
          topic.save!
          topic.publish!
          expect(topic.active_participants_with_visibility.include?(student1)).to be_falsey
          expect(topic.active_participants_with_visibility.include?(student2)).to be_truthy
          expect(topic.active_participants_with_visibility.include?(@teacher)).to be_truthy
        end

        it "works when ungraded and context is a group" do
          group_category = @course.group_categories.create(name: "new cat")
          @group = @course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @topic = @group.discussion_topics.create(title: "group topic")
          @topic.save!

          expect(@topic.context).to eq(@group)
          expect(@topic.active_participants_with_visibility.include?(@student1)).to be_truthy
          expect(@topic.active_participants_with_visibility.include?(@student2)).to be_falsey
        end

        it "includes teachers if a student creates a discussion topic" do
          group_category = @course.group_categories.create(name: "new group")
          @group = @course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @topic = @group.discussion_topics.create(title: "Student topic", user: @student1)
          @topic.save!

          expect(@topic.context).to eq(@group)
          expect(@topic.active_participants_with_visibility.include?(@teacher)).to be_truthy
        end

        it "does not grant reply permissions to group if course is concluded" do
          @relevant_permissions = %i[read reply update delete read_replies]
          group_category = @course.group_categories.create(name: "new cat")
          @group = @course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @course.complete!
          @topic = @group.discussion_topics.create(title: "group topic")
          @topic.save!

          expect(@topic.context).to eq(@group)
          expect((@topic.check_policy(@student1) & @relevant_permissions).sort).to eq [:read, :read_replies].sort
        end

        it "does not grant reply permissions to group if course is soft-concluded" do
          @relevant_permissions = %i[read reply update delete read_replies]
          group_category = @course.group_categories.create(name: "new cat")
          @group = @course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @course.update(start_at: 2.days.ago, conclude_at: 1.day.ago, restrict_enrollments_to_course_dates: true)
          @topic = @group.discussion_topics.create(title: "group topic")
          @topic.save!

          expect(@topic.context).to eq(@group)
          expect((@topic.check_policy(@student1) & @relevant_permissions).sort).to eq [:read, :read_replies].sort
        end

        it "grants reply permissions to group members if course is concluded but their section isn't" do
          @relevant_permissions = %i[read reply update delete read_replies]
          group_category = @course.group_categories.create(name: "new cat")
          @group = @course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @course.update(start_at: 2.days.ago, conclude_at: 1.day.ago, restrict_enrollments_to_course_dates: true)
          @section.update(start_at: 2.days.ago,
                          end_at: 2.days.from_now,
                          restrict_enrollments_to_section_dates: true)
          @topic = @group.discussion_topics.create(title: "group topic")
          @topic.save!

          expect(@topic.context).to eq(@group)
          expect((@topic.check_policy(@student1) & @relevant_permissions).sort).to eq %i[read read_replies reply].sort
        end

        it "does not grant reply permissions to group if group isn't active" do
          @relevant_permissions = %i[read reply update delete read_replies]
          group_category = @course.group_categories.create(name: "new cat")
          @group = @course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @topic = @group.discussion_topics.create(title: "group topic")
          @topic.save!
          @group.destroy

          expect(@topic.reload.context).to eq(@group.reload)
          expect((@topic.check_policy(@student1) & @relevant_permissions).sort).to eq [:read, :read_replies].sort
        end

        it "grants reply permissions to teachers if course is claimed" do
          course = course_factory(active_course: false)
          discussion_topic_model(user: @teacher, context: course)
          course.enroll_teacher(@teacher).accept!
          course.enroll_student(@student1)

          @relevant_permissions = %i[read reply update delete read_replies]
          group_category = course.group_categories.create(name: "new cat")
          @group = course.groups.create(name: "group", group_category:)
          @group.add_user(@student1)
          @topic = @group.discussion_topics.create(title: "group topic")
          @topic.save!

          expect(@topic.context).to eq(@group)
          expect((@topic.check_policy(@teacher) & @relevant_permissions).sort).to eq @relevant_permissions.sort
          expect(@topic.check_policy(@student1) & @relevant_permissions).to be_empty
        end

        it "works for subtopics for graded assignments" do
          group_discussion_assignment
          ct = @topic.child_topics.first
          ct.context.add_user(@student)

          @section = @course.course_sections.create!(name: "test section")
          student_in_section(@section, user: @student)
          create_section_override_for_assignment(@assignment, { course_section: @section })

          @topic = @topic.child_topics.first
          @topic.subscribe(@student)
          @topic.save!

          expect(@topic.context.class).to eq(Group)
          expect(@topic.active_participants_with_visibility.include?(@student)).to be_truthy
        end
      end
    end
  end

  describe "allow_student_discussion_topics setting" do
    before(:once) do
      @topic = @course.discussion_topics.create!(user: @teacher, unlock_at: 1.week.from_now)
      @admin = account_admin_user(account: @course.root_account)
    end

    it "allows students to create topics by default" do
      expect(@topic.check_policy(@teacher)).to include :create
      expect(@topic.check_policy(@admin)).to include :create
      expect(@topic.check_policy(@student)).to include :create
      expect(@topic.check_policy(@course.student_view_student)).to include :create
    end

    it "disallows students from creating topics" do
      @course.allow_student_discussion_topics = false
      @course.save!
      @topic.reload
      expect(@topic.check_policy(@teacher)).to include :create
      expect(@topic.check_policy(@admin)).to include :create
      expect(@topic.check_policy(@student)).not_to include :create
      expect(@topic.check_policy(@course.student_view_student)).not_to include :create
    end
  end

  context "observers" do
    before :once do
      course_with_observer(course: @course, active_all: true)
    end

    it "grants observers read permission by default" do
      @relevant_permissions = %i[read reply update delete]

      @topic = @course.discussion_topics.create!(user: @teacher)
      expect((@topic.check_policy(@observer) & @relevant_permissions).map(&:to_s).sort).to eq ["read"].sort
      @entry = @topic.discussion_entries.create!(user: @teacher)
      expect((@entry.check_policy(@observer) & @relevant_permissions).map(&:to_s).sort).to eq ["read"].sort
    end

    it "does not grant observers read permission when read_forum override is false" do
      RoleOverride.create!(context: @course.account,
                           permission: "read_forum",
                           role: observer_role,
                           enabled: false)

      @relevant_permissions = %i[read reply update delete]
      @topic = @course.discussion_topics.create!(user: @teacher)
      expect((@topic.check_policy(@observer) & @relevant_permissions).map(&:to_s)).to be_empty
      @entry = @topic.discussion_entries.create!(user: @teacher)
      expect((@entry.check_policy(@observer) & @relevant_permissions).map(&:to_s)).to be_empty
    end
  end

  context "delayed posting" do
    before :once do
      @student.register
    end

    def discussion_topic(opts = {})
      workflow_state = opts.delete(:workflow_state)
      @topic = @course.discussion_topics.build(opts)
      @topic.workflow_state = workflow_state if workflow_state
      @topic.save!
      @topic
    end

    def delayed_discussion_topic(opts = {})
      discussion_topic({ workflow_state: "post_delayed" }.merge(opts))
    end

    it "does not send to streams on creation or update if it's delayed" do
      topic = @course.discussion_topics.create!(
        title: "this should not be delayed",
        message: "content here"
      )
      expect(topic.stream_item).not_to be_nil

      topic = delayed_discussion_topic(
        title: "this should be delayed",
        message: "content here",
        delayed_post_at: 1.day.from_now
      )
      expect(topic.stream_item).to be_nil

      topic.message = "content changed!"
      topic.save
      expect(topic.stream_item).to be_nil
    end

    it "sends to streams on update from unpublished to active" do
      topic = discussion_topic(
        title: "this should be delayed",
        message: "content here",
        workflow_state: "unpublished"
      )
      expect(topic.workflow_state).to eq "unpublished"
      expect(topic.stream_item).to be_nil

      topic.workflow_state = "active"
      topic.save!
      expect(topic.stream_item).not_to be_nil
    end

    it "doesn't rely on broadcast policy when sending to stream" do
      topic = discussion_topic(
        title: "this should be delayed",
        message: "content here",
        workflow_state: "unpublished"
      )
      expect(topic.workflow_state).to eq "unpublished"
      expect(topic.stream_item).to be_nil

      topic.workflow_state = "active"
      topic.save_without_broadcasting!
      expect(topic.stream_item).not_to be_nil
    end

    describe "#effective_group_category_id" do
      it "returns the group_category_id if it's set" do
        group_category = @course.group_categories.create!(name: "category")
        topic = @course.discussion_topics.build(title: "Group Topic Title")
        topic.group_category = group_category
        topic.save!

        expect(topic.effective_group_category_id).to eq group_category.id
      end

      it "returns nil if the group_category_id is not set" do
        topic = @course.discussion_topics.build(title: "Topic Title")
        expect(topic.effective_group_category_id).to be_nil
      end
    end

    describe "#update_based_on_date" do
      it "is active when delayed_post_at is in the past" do
        topic = delayed_discussion_topic(title: "title",
                                         message: "content here",
                                         delayed_post_at: 1.day.ago,
                                         lock_at: nil)
        topic.update_based_on_date
        expect(topic.workflow_state).to eql "active"
        expect(topic.locked?).to be_falsey
      end

      it "is post_delayed and remains like than even after publishing when delayed_post_at is in the future" do
        topic = delayed_discussion_topic(title: "title",
                                         message: "content here",
                                         delayed_post_at: 1.day.from_now,
                                         lock_at: nil)
        topic.update_based_on_date
        expect(topic.workflow_state).to eql "post_delayed"
        expect(topic.locked?).to be_falsey
        topic.publish!
        expect(topic.workflow_state).to eql "post_delayed"
      end

      it "is active when lock_at is in the future" do
        topic = delayed_discussion_topic(title: "title",
                                         message: "content here",
                                         delayed_post_at: nil,
                                         lock_at: 1.day.from_now)
        topic.update_based_on_date
        expect(topic.workflow_state).to eql "active"
        expect(topic.locked?).to be_falsey
      end

      it "is active when now is between delayed_post_at and lock_at" do
        topic = delayed_discussion_topic(title: "title",
                                         message: "content here",
                                         delayed_post_at: 1.day.ago,
                                         lock_at: 1.day.from_now)
        topic.update_based_on_date
        expect(topic.workflow_state).to eql "active"
        expect(topic.locked?).to be_falsey
      end

      it "is post_delayed when delayed_post_at and lock_at are in the future" do
        topic = delayed_discussion_topic(title: "title",
                                         message: "content here",
                                         delayed_post_at: 1.day.from_now,
                                         lock_at: 3.days.from_now)
        topic.update_based_on_date
        expect(topic.workflow_state).to eql "post_delayed"
        expect(topic.locked?).to be_falsey
      end

      it "does not unlock a topic even if the lock date is in the future" do
        topic = discussion_topic(title: "title",
                                 message: "content here",
                                 workflow_state: "locked",
                                 locked: true,
                                 delayed_post_at: nil,
                                 lock_at: 1.day.from_now)
        topic.update_based_on_date
        expect(topic.locked?).to be_truthy
      end

      it "does not mark a topic with post_delayed even if delayed_post_at even is in the future" do
        topic = discussion_topic(title: "title",
                                 message: "content here",
                                 workflow_state: "active",
                                 delayed_post_at: 1.day.from_now,
                                 lock_at: nil)
        topic.update_based_on_date
        expect(topic.workflow_state).to eql "active"
        expect(topic.locked?).to be_falsey
      end
    end
  end

  context "sub-topics" do
    it "defaults subtopics_refreshed_at on save if a group discussion" do
      group_category = @course.group_categories.create(name: "category")
      @group = @course.groups.create(name: "group", group_category:)
      @topic = @course.discussion_topics.create(title: "topic")
      expect(@topic.subtopics_refreshed_at).to be_nil

      @topic.group_category = group_category
      @topic.save
      expect(@topic.subtopics_refreshed_at).not_to be_nil
    end

    it "does not allow anyone to edit sub-topics" do
      @first_user = @student
      @second_user = user_model
      @course.enroll_student(@second_user).accept
      @parent_topic = @course.discussion_topics.create!(title: "parent topic", message: "msg")
      @group = @course.groups.create!(name: "course group")
      @group.add_user(@first_user)
      @group.add_user(@second_user)
      @group_topic = @group.discussion_topics.create!(title: "group topic", message: "ok to be edited", user: @first_user)
      @sub_topic = @group.discussion_topics.build(title: "sub topic", message: "not ok to be edited", user: @first_user)
      @sub_topic.root_topic_id = @parent_topic.id
      @sub_topic.save!
      expect(@group_topic.grants_right?(@second_user, :update)).to be(false)
      expect(@sub_topic.grants_right?(@second_user, :update)).to be(false)
      expect(@group_topic.grants_right?(@teacher, :update)).to be(true)
      expect(@sub_topic.grants_right?(@teacher, :update)).to be(false) # the changes just get undone anyway by refresh_subtopics
    end
  end

  context "refresh_subtopics" do
    it "is a no-op unless it has a group_category" do
      @topic = @course.discussion_topics.create(title: "topic")
      @topic.refresh_subtopics
      expect(@topic.reload.child_topics).to be_empty

      @topic.assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title)
      @topic.assignment.saved_by = :discussion_topic
      @topic.save
      @topic.refresh_subtopics
      expect(@topic.reload.child_topics).to be_empty
    end

    it "refreshes when groups are added to a group_category" do
      group_category = @course.group_categories.create!(name: "category")

      topic = @course.discussion_topics.build(title: "topic")
      topic.group_category = group_category
      topic.save!

      group = @course.groups.create!(name: "group 1", group_category:)
      expect(topic.reload.child_topics.size).to eq 1
      expect(group.reload.discussion_topics.size).to eq 1
    end

    it "does not break when groups have silly long names" do
      group_category = @course.group_categories.create!(name: "category")

      topic = @course.discussion_topics.build(title: "here's a reasonable topic name")
      topic.group_category = group_category
      topic.save!

      group = @course.groups.create!(name: "a" * 250, group_category:)
      expect(topic.reload.child_topics.size).to eq 1
      expect(group.reload.discussion_topics.size).to eq 1
    end

    it "deletes child topics when group category is removed" do
      group_category = @course.group_categories.create!(name: "category")
      group = @course.groups.create!(name: "group 1", group_category:)

      topic = @course.discussion_topics.build(title: "topic")
      topic.group_category = group_category
      topic.save!

      expect(topic.reload.child_topics.active.count).to eq 1
      expect(group.reload.discussion_topics.active.count).to eq 1

      topic.group_category = nil
      topic.save!

      expect(topic.reload.child_topics.active.count).to eq 0
      expect(group.reload.discussion_topics.active.count).to eq 0
    end

    context "in a group discussion" do
      before :once do
        group_discussion_assignment
      end

      it "creates a topic per active group in the category otherwise" do
        @topic.refresh_subtopics
        subtopics = @topic.reload.child_topics
        expect(subtopics).not_to be_nil
        expect(subtopics.size).to eq 2
        subtopics.each { |t| expect(t.root_topic).to eq @topic }
        expect(@group1.reload.discussion_topics).not_to be_empty
        expect(@group2.reload.discussion_topics).not_to be_empty
      end

      it "copies appropriate attributes from the parent topic to subtopics on updates to the parent" do
        @topic.refresh_subtopics
        subtopics = @topic.reload.child_topics
        subtopics.each do |st|
          expect(st.discussion_type).to eq "threaded"
          expect(st.attachment_id).to be_nil
        end

        attachment_model(context: @course)
        @topic.discussion_type = "threaded"
        @topic.attachment = @attachment
        @topic.save!
        subtopics = @topic.reload.child_topics
        subtopics.each do |st|
          expect(st.discussion_type).to eq "threaded"
          expect(st.attachment_id).to eq @attachment.id
        end
      end

      it "does not rename the assignment to match a subtopic" do
        original_name = @assignment.title
        @assignment.reload
        expect(@assignment.title).to eq original_name
      end
    end
  end

  context "root_topic?" do
    it "is false if the topic has a root topic" do
      # subtopic has the assignment and group_category, but has a root topic
      group_category = @course.group_categories.create(name: "category")
      @parent_topic = @course.discussion_topics.create(title: "parent topic")
      @parent_topic.group_category = group_category
      @subtopic = @parent_topic.child_topics.build(title: "subtopic")
      @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @subtopic.title)
      @assignment.infer_times
      @assignment.saved_by = :discussion_topic
      @subtopic.assignment = @assignment
      @subtopic.group_category = group_category
      @subtopic.save

      expect(@subtopic).not_to be_root_topic
    end

    it "is false unless the topic has an assignment" do
      # topic has no root topic, but also has no assignment
      @topic = @course.discussion_topics.create(title: "subtopic")
      expect(@topic).not_to be_root_topic
    end

    it "is false unless the topic has a group_category" do
      # topic has no root topic and has an assignment, but the assignment has no group_category
      @topic = @course.discussion_topics.create(title: "topic")
      @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title)
      @assignment.infer_times
      @assignment.saved_by = :discussion_topic
      @topic.assignment = @assignment
      @topic.save

      expect(@topic).not_to be_root_topic
    end

    it "is true otherwise" do
      # topic meets all criteria
      group_category = @course.group_categories.create(name: "category")
      @topic = @course.discussion_topics.create(title: "topic")
      @topic.group_category = group_category
      @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title)
      @assignment.infer_times
      @assignment.saved_by = :discussion_topic
      @topic.assignment = @assignment
      @topic.save

      expect(@topic).to be_root_topic
    end
  end

  describe "#discussion_subentry_count" do
    it "returns the count of all active discussion_entries" do
      @topic = @course.discussion_topics.create(title: "topic")
      @topic.reply_from(user: @teacher, text: "entry 1").destroy  # no count
      @topic.reply_from(user: @teacher, text: "entry 1")          # 1
      @entry = @topic.reply_from(user: @teacher, text: "entry 2") # 2
      @entry.reply_from(user: @student, html: "reply 1")          # 3
      @entry.reply_from(user: @student, html: "reply 2")          # 4
      # expect
      expect(@topic.discussion_subentry_count).to eq 4
    end
  end

  context "for_assignment?" do
    it "is not for_assignment? unless it has an assignment" do
      @topic = @course.discussion_topics.create(title: "topic")
      expect(@topic).not_to be_for_assignment

      @topic.assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title)
      @topic.assignment.infer_times
      @topic.assignment.saved_by = :discussion_topic
      @topic.save
      expect(@topic).to be_for_assignment
    end
  end

  context "for_group_discussion?" do
    it "is not for_group_discussion? unless it has a group_category" do
      course_with_student(active_all: true)
      @topic = @course.discussion_topics.build(title: "topic")
      @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title)
      @assignment.infer_times
      @assignment.saved_by = :discussion_topic
      @topic.assignment = @assignment
      @topic.save
      expect(@topic).not_to be_for_group_discussion

      @topic.group_category = @course.group_categories.create(name: "category")
      @topic.save
      expect(@topic).to be_for_group_discussion
    end
  end

  context "should_send_to_stream" do
    context "in a published course" do
      it "is true for non-assignment discussions" do
        @topic = @course.discussion_topics.create(title: "topic")
        expect(@topic.should_send_to_stream).to be_truthy
      end

      it "is true for non-group discussion assignments" do
        @topic = @course.discussion_topics.build(title: "topic")
        @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title, due_at: 1.day.from_now)
        @assignment.saved_by = :discussion_topic
        @topic.assignment = @assignment
        @topic.save
        expect(@topic.should_send_to_stream).to be_truthy
      end

      it "is true for the parent topic only in group discussions, not the subtopics" do
        group_category = @course.group_categories.create(name: "category")
        @parent_topic = @course.discussion_topics.create(title: "parent topic")
        @parent_topic.group_category = group_category
        @parent_topic.save
        @subtopic = @parent_topic.child_topics.build(title: "subtopic")
        @subtopic.group_category = group_category
        @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @subtopic.title, due_at: 1.day.from_now)
        @assignment.saved_by = :discussion_topic
        @subtopic.assignment = @assignment
        @subtopic.save
        expect(@parent_topic.should_send_to_stream).to be_truthy
        expect(@subtopic.should_send_to_stream).to be_falsey
      end
    end

    it "does not send stream items to students if locked by a module" do
      topic = @course.discussion_topics.create!(
        title: "Ya Ya Ding Dong",
        user: @teacher,
        message: "By Will Ferrell and My Marianne",
        workflow_state: "unpublished"
      )

      context_module = @course.context_modules.create!(name: "some module")
      context_module.unlock_at = 1.day.from_now
      context_module.add_item(type: "discussion_topic", id: topic.id)
      context_module.save!
      topic.publish!

      expect(@student.stream_item_instances.count).to eq 0
    end

    it "does not send stream items to students if course isn't published'" do
      @course.update_attribute(:workflow_state, "created")
      topic = @course.discussion_topics.create!(title: "secret topic", user: @teacher)

      expect(@student.stream_item_instances.count).to eq 0
      expect(@teacher.stream_item_instances.count).to eq 1

      topic.discussion_entries.create!

      expect(@student.stream_item_instances.count).to eq 0
      expect(@teacher.stream_item_instances.count).to eq 1
    end

    it "sends stream items to participating students" do
      expect { @course.discussion_topics.create!(title: "topic", user: @teacher) }.to change { @student.stream_item_instances.count }.by(1)
    end

    it "removes stream items from users removed from the discussion" do
      section1 = @course.course_sections.create!
      section2 = @course.course_sections.create!
      student1 = create_enrolled_user(@course, section1, name: "student 1", enrollment_type: "StudentEnrollment")
      student2 = create_enrolled_user(@course, section2, name: "student 2", enrollment_type: "StudentEnrollment")
      topic = @course.discussion_topics.create!(title: "Ben Loves Panda", user: @teacher)
      add_section_to_topic(topic, section1)
      add_section_to_topic(topic, section2)
      topic.save!
      topic.publish!
      expect(student1.stream_item_instances.count).to eq 1
      expect(student2.stream_item_instances.count).to eq 1

      expect do
        topic.update!(course_sections: [section1])
      end.to change {
        student2.stream_item_instances.count
      }.from(1).to(0).and not_change(student1.stream_item_instances, :count)
    end

    it "removes streams when a student is unassigned from the discussion" do
      section1 = @course.course_sections.create!
      @student1 = create_enrolled_user(@course, section1, name: "student 1", enrollment_type: "StudentEnrollment")
      topic = @course.discussion_topics.create!(title: "Discussion", user: @teacher, only_visible_to_overrides: true)
      topic.overrides_changed = true

      override = topic.assignment_overrides.create!
      override.assignment_override_students.create!(user: @student1)

      expect(@student.stream_item_instances.count).to eq 1

      topic.assignment_overrides.last.destroy
      topic.save!

      expect(@student.stream_item_instances.count).to eq 0
    end

    it "removes stream items from users if updated to a delayed post in the future" do
      announcement = @course.announcements.create!(title: "Lemon Loves Panda", message: "Because panda is home")

      expect(@student.stream_item_instances.count).to eq 1

      announcement.delayed_post_at = 5.days.from_now
      announcement.workflow_state = "post_delayed"
      announcement.save!

      expect(@student.stream_item_instances.count).to eq 0
    end

    it "removes stream items from users if locked by a module" do
      topic = @course.discussion_topics.create!(title: "Ya Ya Ding Dong", user: @teacher, message: "By Will Ferrell and My Marianne")

      expect(@student.stream_item_instances.count).to eq 1

      context_module = @course.context_modules.create!(name: "some module")
      context_module.unlock_at = 1.day.from_now
      context_module.add_item(type: "discussion_topic", id: topic.id)
      context_module.save!
      topic.save!

      expect(@student.stream_item_instances.count).to eq 0
    end

    it "does not attempt to clear stream items if a discussion topic was not section specific before last save" do
      topic = @course.discussion_topics.create!(title: "Ben Loves Panda", user: @teacher)
      expect(topic.stream_item).not_to receive(:stream_item_instances)
      topic.update!(title: "Lemon Loves Panda")
    end

    it "does not send stream items to students if the topic isn't published" do
      topic = nil
      expect { topic = @course.discussion_topics.create!(title: "secret topic", user: @teacher, workflow_state: "unpublished") }.not_to change { @student.stream_item_instances.count }
      expect { topic.discussion_entries.create! }.not_to change { @student.stream_item_instances.count }
    end

    it "does not send stream items to students if the topic is not available yet" do
      topic = nil
      expect { topic = @course.discussion_topics.create!(title: "secret topic", user: @teacher, delayed_post_at: 1.week.from_now) }.not_to change { @student.stream_item_instances.count }
      expect { topic.discussion_entries.create! }.not_to change { @student.stream_item_instances.count }
    end

    it "sends stream items to students for graded discussions" do
      @topic = @course.discussion_topics.build(title: "topic")
      @assignment = @course.assignments.build(submission_types: "discussion_topic", title: @topic.title)
      @assignment.saved_by = :discussion_topic
      @topic.assignment = @assignment
      @topic.save

      expect(@student.stream_item_instances.count).to eq 1
    end

    it "doesn't send stream items for students that aren't assigned" do
      @empty_section = @course.course_sections.create!
      @topic = @course.discussion_topics.build(title: "topic")
      @assignment = @course.assignments.build title: @topic.title,
                                              submission_types: "discussion_topic",
                                              only_visible_to_overrides: true
      @assignment.assignment_overrides.build set: @empty_section
      @assignment.saved_by = :discussion_topic
      @topic.assignment = @assignment
      @topic.save
      expect(@student.stream_item_instances.count).to eq 0
    end
  end

  context "posting first to view" do
    before(:once) do
      @observer = user_factory(active_all: true)
      @context = @course
      discussion_topic_model
      @topic.require_initial_post = true
      @topic.save
    end

    it "allows admins to see posts without posting" do
      expect(@topic.user_can_see_posts?(@teacher)).to be true
    end

    it "allows course admins to see posts in concluded group topics without posting" do
      group_category = @course.group_categories.create(name: "category")
      @group = @course.groups.create(name: "group", group_category:)
      @topic.update_attribute(:group_category, group_category)
      subtopic = @topic.child_topics.first
      @course.complete!
      expect(subtopic.user_can_see_posts?(@teacher)).to be true
    end

    it "only allows active admins to see posts without posting" do
      @ta_enrollment = course_with_ta(course: @course, active_enrollment: true)
      # TA should be able to see
      expect(@topic.user_can_see_posts?(@ta)).to be true
      # Remove user as TA and enroll as student, should not be able to see
      @ta_enrollment.destroy
      # enroll as a student.
      course_with_student(course: @course, user: @ta, active_enrollment: true)
      @topic.reload
      @topic.clear_permissions_cache(@ta)
      expect(@topic.user_can_see_posts?(@ta)).to be false
    end

    it "does not allow student who hasn't posted to see" do
      expect(@topic.user_can_see_posts?(@student)).to be false
    end

    it "does not allow participation in deleted discussions" do
      @topic.destroy
      expect { @topic.discussion_entries.create!(message: "second message", user: @student) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { @topic.discussion_entries.create!(message: "second message", user: @teacher) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "throws incomingMail error when reply to deleted discussion" do
      @topic.destroy
      expect { @topic.reply_from(user: @teacher, text: "hai") }.to raise_error(IncomingMail::Errors::ReplyToDeletedDiscussion)
      expect { @topic.reply_from(user: @student, text: "hai") }.to raise_error(IncomingMail::Errors::ReplyToDeletedDiscussion)
    end

    it "allows student who has posted to see" do
      @topic.reply_from(user: @student, text: "hai")
      expect(@topic.user_can_see_posts?(@student)).to be true
    end

    it "works the same for group discussions" do
      group_discussion_assignment
      @topic.require_initial_post = true
      @topic.save!
      ct = @topic.child_topics.first
      ct.context.add_user(@student)
      expect(ct.user_can_see_posts?(@student)).to be_falsey
      ct.reply_from(user: @student, text: "ohai")
      ct.user_ids_who_have_posted_and_admins
      expect(ct.user_can_see_posts?(@student)).to be_truthy
    end

    it "lets account admins see group discussions with require_initial_post" do
      group_discussion_assignment
      @topic.require_initial_post = true
      @topic.save!
      ct = @topic.child_topics.first
      account_admin_user(active_all: true)
      expect(ct.user_can_see_posts?(@admin)).to be_truthy
    end

    describe "observers" do
      before :once do
        @other_student = user_factory(active_all: true)
        @course.enroll_student(@other_student, enrollment_state: "active")
        @course.enroll_user(@observer,
                            "ObserverEnrollment",
                            associated_user_id: @student,
                            enrollment_state: "active")
        @course.enroll_user(@observer,
                            "ObserverEnrollment",
                            associated_user_id: @other_student,
                            enrollment_state: "active")
      end

      it "does not allow observers to see replies to a discussion linked students haven't posted in" do
        expect(@topic.initial_post_required?(@observer)).to be
      end

      # previously this worked for exactly one observer enrollment, whichever became @context_enrollment
      # so test both ways
      it "allows observers to see replies in a discussion a linked student has posted in (1/2)" do
        @topic.reply_from(user: @student, text: "wat")
        expect(@topic.initial_post_required?(@observer)).not_to be
      end

      it "allows observers to see replies in a discussion a linked student has posted in (2/2)" do
        @topic.reply_from(user: @other_student, text: "wat")
        expect(@topic.initial_post_required?(@observer)).not_to be
      end
    end
  end

  context "subscribers" do
    before :once do
      @context = @course
      discussion_topic_model(user: @teacher)
    end

    it "automatically includes the author" do
      expect(@topic.subscribers).to include(@teacher)
    end

    it "does not include the author if they unsubscribe" do
      @topic.unsubscribe(@teacher)
      expect(@topic.subscribers).not_to include(@teacher)
    end

    it "automatically includes posters" do
      @topic.reply_from(user: @student, text: "entry")
      expect(@topic.subscribers).to include(@student)
    end

    it "includes author when topic was created before subscriptions where added" do
      participant = @topic.update_or_create_participant(current_user: @topic.user, subscribed: nil)
      expect(participant.subscribed).to be_nil
      expect(@topic.subscribers.map(&:id)).to include(@teacher.id)
    end

    it "includes users that have posted entries before subscriptions were added" do
      @topic.reply_from(user: @student, text: "entry")
      participant = @topic.update_or_create_participant(current_user: @student, subscribed: nil)
      expect(participant.subscribed).to be_nil
      expect(@topic.subscribers.map(&:id)).to include(@student.id)
    end

    it "does not include posters if they unsubscribe" do
      @topic.reply_from(user: @student, text: "entry")
      @topic.unsubscribe(@student)
      expect(@topic.subscribers).not_to include(@student)
    end

    it "resubscribes unsubscribed users if they post" do
      @topic.reply_from(user: @student, text: "entry")
      @topic.unsubscribe(@student)
      @topic.reply_from(user: @student, text: "another entry")
      expect(@topic.subscribers).to include(@student)
    end

    it "includes users who subscribe" do
      @topic.subscribe(@student)
      expect(@topic.subscribers).to include(@student)
    end

    it "does not include anyone no longer in the course" do
      @topic.subscribe(@student)
      @topic2 = @course.discussion_topics.create!(title: "student topic", message: "I'm outta here", user: @student)
      @student.enrollments.first.destroy
      expect(@topic.subscribers).not_to include(@student)
      expect(@topic2.subscribers).not_to include(@student)
    end

    context "differentiated_assignments" do
      before do
        @assignment = @course.assignments.create!(title: "some discussion assignment", only_visible_to_overrides: true)
        @assignment.submission_types = "discussion_topic"
        @assignment.save!
        @topic.assignment_id = @assignment.id
        @topic.save!
        @section = @course.course_sections.create!(name: "test section")
        create_section_override_for_assignment(@topic.assignment, { course_section: @section })
      end

      context "enabled" do
        it "filters subscribers based on visibility" do
          @topic.subscribe(@student)
          expect(@topic.subscribers).not_to include(@student)
          student_in_section(@section, user: @student)
          expect(@topic.subscribers).to include(@student)
        end

        it "filters observers if their student cant see" do
          @observer = user_factory(active_all: true, name: "Observer")
          observer_enrollment = @course.enroll_user(@observer, "ObserverEnrollment", section: @section, enrollment_state: "active")
          observer_enrollment.update_attribute(:associated_user_id, @student.id)
          @topic.subscribe(@observer)
          expect(@topic.subscribers.include?(@observer)).to be_falsey
          student_in_section(@section, user: @student)
          expect(@topic.subscribers.include?(@observer)).to be_truthy
        end

        it "doesnt filter for observers with no student" do
          @observer = user_factory(active_all: true)
          @course.enroll_user(@observer, "ObserverEnrollment", section: @section, enrollment_state: "active")
          @topic.subscribe(@observer)
          expect(@topic.subscribers).to include(@observer)
        end

        it "works for graded subtopics" do
          group_discussion_assignment
          ct = @topic.child_topics.first
          ct.context.add_user(@student)

          @topic = @topic.child_topics.first
          @topic.subscribe(@student)
          @topic.save!

          expect(@topic.subscribers).to include(@student)
        end
      end
    end
  end

  context "visible_to_students_in_course_with_da" do
    before :once do
      @context = @course
      discussion_topic_model(user: @teacher)
      @assignment = @course.assignments.create!(title: "some discussion assignment", only_visible_to_overrides: true)
      @assignment.submission_types = "discussion_topic"
      @assignment.save!
      @topic.assignment_id = @assignment.id
      @topic.save!
      @section = @course.course_sections.create!(name: "test section")
      @student = create_users(1, return_type: :record).pop
      student_in_section(@section, user: @student)
    end

    it "returns discussions that have assignment and visibility" do
      create_section_override_for_assignment(@topic.assignment, { course_section: @section })
      expect(DiscussionTopic.visible_to_students_in_course_with_da([@student.id], [@course.id])).to include(@topic)
    end

    it "returns discussions that have no assignment" do
      @topic.assignment_id = nil
      @topic.save!
      expect(DiscussionTopic.visible_to_students_in_course_with_da([@student.id], [@course.id])).to include(@topic)
    end

    it "does not return discussions that have an assignment and no visibility" do
      expect(DiscussionTopic.visible_to_students_in_course_with_da([@student.id], [@course.id])).not_to include(@topic)
    end

    describe "differentiated modules" do
      context "ungraded discussions" do
        before do
          @topic = discussion_topic_model(user: @teacher, context: @course)
          @topic.update!(only_visible_to_overrides: true)
          @course_section = @course.course_sections.create
          @student1 = student_in_course(course: @course, active_enrollment: true).user
          @student2 = student_in_course(course: @course, active_enrollment: true, section: @course_section).user
          @teacher1 = teacher_in_course(course: @course, active_enrollment: true).user
          @teacher2_limited_to_section = teacher_in_course(course: @course, active_enrollment: true).user
          Enrollment.limit_privileges_to_course_section!(@course, @teacher2_limited_to_section, true)
        end

        it "is visible only to the assigned student" do
          override = @topic.assignment_overrides.create!
          override.assignment_override_students.create!(user: @student1)

          expect(DiscussionTopic.visible_to_students_in_course_with_da([@student1.id], [@course.id])).to include(@topic)
          expect(DiscussionTopic.visible_to_students_in_course_with_da([@student2.id], [@course.id])).not_to include(@topic)
          expect(@topic.active_participants_with_visibility).to include(@student1)
          expect(@topic.active_participants_with_visibility).not_to include(@student2)
        end

        it "is visible only to users who can access the assigned section" do
          @topic.assignment_overrides.create!(set: @course_section)
          expect(DiscussionTopic.visible_to_students_in_course_with_da([@student1.id], [@course.id])).not_to include(@topic)
          expect(DiscussionTopic.visible_to_students_in_course_with_da([@student2.id], [@course.id])).to include(@topic)
          expect(@topic.active_participants_with_visibility).not_to include(@student1)
          expect(@topic.active_participants_with_visibility).to include(@student2)
        end

        it "is visible only to students in module override section" do
          context_module = @course.context_modules.create!(name: "module")
          context_module.content_tags.create!(content: @topic, context: @course)

          override2 = @topic.assignment_overrides.create!(unlock_at: "2022-02-01T01:00:00Z",
                                                          unlock_at_overridden: true,
                                                          lock_at: "2022-02-02T01:00:00Z",
                                                          lock_at_overridden: true)
          override2.assignment_override_students.create!(user: @student1)

          expect(DiscussionTopic.visible_to_students_in_course_with_da([@student1.id], [@course.id])).to include(@topic)
          expect(DiscussionTopic.visible_to_students_in_course_with_da([@student2.id], [@course.id])).not_to include(@topic)
        end
      end
    end
  end

  context "posters" do
    before :once do
      @context = @course
      discussion_topic_model(user: @teacher)
    end

    it "includes the topic author" do
      expect(@topic.posters).to include(@teacher)
    end

    it "includes users that have posted entries" do
      @student = student_in_course(active_all: true).user
      @topic.reply_from(user: @student, text: "entry")
      expect(@topic.posters).to include(@student)
    end

    it "includes users that have replies to entries" do
      @entry = @topic.reply_from(user: @teacher, text: "entry")
      @student = student_in_course(active_all: true).user
      @entry.reply_from(user: @student, html: "reply")

      @topic.reload
      expect(@topic.posters).to include(@student)
    end

    it "dedupes users" do
      @entry = @topic.reply_from(user: @teacher, text: "entry")
      @student = student_in_course(active_all: true).user
      @entry.reply_from(user: @student, html: "reply 1")
      @entry.reply_from(user: @student, html: "reply 2")

      @topic.reload
      expect(@topic.posters).to include(@teacher)
      expect(@topic.posters).to include(@student)
      expect(@topic.posters.size).to eq 2
    end

    it "does not include topic author if she is no longer enrolled in the course" do
      student_in_course(active_all: true)
      @topic2 = @course.discussion_topics.create!(title: "student topic", message: "I'm outta here", user: @student)
      @entry = @topic2.discussion_entries.create!(message: "go away", user: @teacher)
      expect(@topic2.posters.map(&:id).sort).to eql [@student.id, @teacher.id].sort
      @student.enrollments.first.destroy
      expect(@topic2.posters.map(&:id).sort).to eql [@teacher.id].sort
    end
  end

  context "submissions when graded" do
    before :once do
      @context = @course
      discussion_topic_model(user: @teacher)
    end

    def build_submitted_assignment
      @assignment = @course.assignments.create!(title: "some discussion assignment")
      @assignment.submission_types = "discussion_topic"
      @assignment.save!
      @topic.assignment_id = @assignment.id
      @topic.save!
      @entry1 = @topic.discussion_entries.create!(message: "second message", user: @student)
      @entry1.created_at = 1.week.ago
      @entry1.save!
      @submission = @assignment.submissions.where(user_id: @entry1.user_id).first
    end

    it "does not re-flag graded discussion as needs grading if student make another comment" do
      assignment = @course.assignments.create(title: "discussion assignment", points_possible: 20)
      topic = @course.discussion_topics.create!(title: "discussion topic 1", message: "this is a new discussion topic", assignment:)
      topic.discussion_entries.create!(message: "student message for grading", user: @student)

      submissions = Submission.where(user_id: @student, assignment_id: assignment).to_a
      expect(submissions.count).to eq 1
      student_submission = submissions.first
      assignment.grade_student(@student, grade: 9, grader: @teacher)
      student_submission.reload
      expect(student_submission.workflow_state).to eq "graded"

      topic.discussion_entries.create!(message: "student message 2 for grading", user: @student)
      submissions = Submission.where(user_id: @student, assignment_id: assignment).to_a
      expect(submissions.count).to eq 1
      student_submission = submissions.first
      expect(student_submission.workflow_state).to eq "graded"
    end

    it "creates submissions for existing entries when setting the assignment (even if locked)" do
      entry = @topic.reply_from(user: @student, text: "entry")
      @student.reload
      expect(@student.submissions).to be_empty

      entry_time = 1.minute.ago
      DiscussionEntry.where(id: entry.id).update_all(created_at: entry_time)
      @assignment = assignment_model(course: @course, lock_at: 1.day.ago, due_at: 2.days.ago)
      @topic.assignment = @assignment
      @topic.save
      @student.reload
      expect(@student.submissions.size).to eq 1
      sub = @student.submissions.first
      expect(sub.submission_type).to eq "discussion_topic"
      expect(sub.submitted_at).to eq entry_time # the submission time should be backdated to the entry creation time
    end

    it "uses fancy midnight" do
      @topic.update!(lock_at: Time.zone.parse("Sat, 31 Mar 2018"))
      expect(@topic.lock_at.hour).to eq 23
      expect(@topic.lock_at.min).to eq 59
      expect(@topic.lock_at.sec).to eq 59
    end

    it "uses fancy midnight relative to the context time_zone" do
      zone = "America/New_York"
      context = @topic.context
      context.update(time_zone: zone)
      @topic.update!(lock_at: Time.zone.parse("Sat, 31 Mar 2018"))
      expect(@topic.lock_at.hour).to eq 0
      expect(@topic.lock_at.min).to eq 0
      expect(@topic.lock_at.sec).to eq 0
      @topic.update!(lock_at: Time.zone.parse("Sat, 31 Mar 2018 4:00:00"))
      expect(@topic.lock_at.hour).to eq 3
      expect(@topic.lock_at.min).to eq 59
      expect(@topic.lock_at.sec).to eq 59
    end

    it "creates submissions for existing entries in group topics when setting the assignment (even if locked)" do
      group_category = @course.group_categories.create!(name: "category")
      @group1 = @course.groups.create!(name: "group 1", group_category:)

      @topic.group_category = group_category
      @topic.save!

      child_topic = @topic.child_topics.first
      child_topic.context.add_user(@student)
      child_topic.reply_from(user: @student, text: "entry")
      @student.reload
      expect(@student.submissions).to be_empty

      @assignment = assignment_model(course: @course, lock_at: 1.day.ago, due_at: 2.days.ago)
      @topic.assignment = @assignment
      @topic.save
      @student.reload
      expect(@student.submissions.size).to eq 1
      expect(@student.submissions.first.submission_type).to eq "discussion_topic"
    end

    it "creates use entry time when groupless students are (for whatever reason) posting to a graded group discussion" do
      group_category = @course.group_categories.create!(name: "category")
      @group1 = @course.groups.create!(name: "group 1", group_category:)

      @topic.group_category = group_category
      @topic.save!

      entry = @topic.reply_from(user: @student, text: "entry")
      @student.reload
      expect(@student.submissions).to be_empty

      entry_time = 1.minute.ago
      DiscussionEntry.where(id: entry.id).update_all(created_at: entry_time)
      @assignment = assignment_model(course: @course, lock_at: 1.day.ago, due_at: 2.days.ago)
      @topic.assignment = @assignment
      @topic.save
      @student.reload
      expect(@student.submissions.size).to eq 1
      sub = @student.submissions.first
      expect(sub.submission_type).to eq "discussion_topic"
      expect(sub.submitted_at).to eq entry_time # the submission time should be backdated to the entry creation time
    end

    it "has the correct submission date if submission has comment" do
      @assignment = @course.assignments.create!(title: "some discussion assignment")
      @assignment.submission_types = "discussion_topic"
      @assignment.save!
      @topic.assignment = @assignment
      @topic.save
      @submission = @assignment.find_or_create_submission(@student.id)
      @submission_comment = @submission.add_comment(author: @teacher, comment: "some comment")
      @submission.created_at = 1.week.ago
      @submission.save!
      expect(@submission.workflow_state).to eq "unsubmitted"
      expect(@submission.submitted_at).to be_nil
      @entry = @topic.discussion_entries.create!(message: "somne discussion message", user: @student)
      @submission.reload
      expect(@submission.workflow_state).to eq "submitted"
      expect(@submission.submitted_at.to_i).to be >= @entry.created_at.to_i # this time may not be exact because it goes off of time.now in the submission
    end

    it "fixes submission date after deleting the oldest entry" do
      build_submitted_assignment
      @entry2 = @topic.discussion_entries.create!(message: "some message", user: @student)
      @entry2.created_at = 1.day.ago
      @entry2.save!
      @entry1.destroy
      @topic.reload
      expect(@topic.discussion_entries).not_to be_empty
      expect(@topic.discussion_entries.active).not_to be_empty
      @submission.reload
      expect(@submission.submitted_at.to_i).to eq @entry2.created_at.to_i
      expect(@submission.workflow_state).to eq "submitted"
    end

    it "marks submission as unsubmitted after deletion" do
      build_submitted_assignment
      @entry1.destroy
      @topic.reload
      expect(@topic.discussion_entries).not_to be_empty
      expect(@topic.discussion_entries.active).to be_empty
      @submission.reload
      expect(@submission.workflow_state).to eq "unsubmitted"
      expect(@submission.submission_type).to be_nil
      expect(@submission.submitted_at).to be_nil
    end

    it "has new submission date after deletion and re-submission" do
      build_submitted_assignment
      @entry1.destroy
      @topic.reload
      expect(@topic.discussion_entries).not_to be_empty
      expect(@topic.discussion_entries.active).to be_empty
      @entry2 = @topic.discussion_entries.create!(message: "some message", user: @student)
      @submission.reload
      expect(@submission.submitted_at.to_i).to be >= @entry2.created_at.to_i # this time may not be exact because it goes off of time.now in the submission
      expect(@submission.workflow_state).to eq "submitted"
    end

    it "does not duplicate submissions for existing entries that already have submissions" do
      @assignment = assignment_model(course: @course)
      @topic.assignment = @assignment
      @topic.save
      @topic.reload # to get the student in topic.assignment.context.students

      @topic.reply_from(user: @student, text: "entry")
      @student.reload
      expect(@student.submissions.size).to eq 1
      @existing_submission_id = @student.submissions.first.id

      @topic.assignment = nil
      @topic.save
      @topic.reply_from(user: @student, text: "another entry")
      @student.reload
      expect(@student.submissions.size).to eq 1
      expect(@student.submissions.first.id).to eq @existing_submission_id

      @topic.assignment = @assignment
      @topic.save
      @student.reload
      expect(@student.submissions.size).to eq 1
      expect(@student.submissions.first.id).to eq @existing_submission_id
    end

    it "does not resubmit graded discussion submissions" do
      @assignment = assignment_model(course: @course)
      @topic.assignment = @assignment
      @topic.save!
      @topic.reload

      @topic.reply_from(user: @student, text: "entry")
      @student.reload

      @assignment.grade_student(@student, grade: 1, grader: @teacher)
      @submission = Submission.where(user_id: @student, assignment_id: @assignment).first
      expect(@submission.workflow_state).to eq "graded"

      @topic.ensure_submission(@student)
      expect(@submission.reload.workflow_state).to eq "graded"
    end

    it "associates attachments with graded discussion submissions" do
      @assignment = assignment_model(course: @course)
      @topic.assignment = @assignment
      @topic.save!
      @topic.reload

      attachment_model(context: @user, uploaded_data: stub_png_data, filename: "homework.png")
      entry = @topic.reply_from(user: @student, text: "entry")
      entry.attachment = @attachment
      entry.save!

      @topic.ensure_submission(@student)
      sub = @assignment.submissions.where(user_id: @student).first
      expect(sub.attachments.to_a).to eq [@attachment]

      entry.destroy
      expect(sub.reload.attachments.to_a).to eq [] # should update the attachments right away and not depend on another entry being created
    end

    it "associates attachments with graded discussion submissions even with silly deleted topics" do
      gc1 = group_category(name: "gc1")
      group_with_user(group_category: gc1, user: @student, context: @course)
      gc2 = group_category(name: "gc2")
      group_with_user(group_category: gc2, user: @student, context: @course)
      group2 = @group

      @assignment = assignment_model(course: @course)
      @topic.assignment = @assignment
      @topic.group_category = gc1
      @topic.save!
      @topic.group_category = gc2 # switching group categories deletes the old child topics
      @topic.save!
      @topic.reload

      # can't use child_topic_for to show the exact bug
      # because that's where the reported bug is
      sub_topic = @topic.child_topics.where(context_type: "Group", context_id: group2).first

      attachment_model(context: @user, uploaded_data: stub_png_data, filename: "homework.png")
      entry = sub_topic.reply_from(user: @student, text: "entry")
      entry.attachment = @attachment
      entry.save!

      sub = @assignment.submissions.where(user_id: @student).first
      expect(sub.attachments.to_a).to eq [@attachment]
    end
  end

  describe "#unread_count" do
    let(:topic) do
      @course.discussion_topics.create!(title: "title", message: "message")
    end

    it "returns 0 for a nil user" do
      topic.discussion_entries.create!
      expect(topic.unread_count(nil)).to eq 0
    end

    it "returns the default_unread_count if the user has no discussion_topic_participant" do
      topic.discussion_entries.create!
      student_in_course
      expect(topic.unread_count(@student)).to eq 1
    end
  end

  context "read/unread state" do
    def check_read_state_scopes(read: false, user: nil)
      return unless user

      if read
        expect(DiscussionTopic.read_for(user)).to include @topic
        expect(DiscussionTopic.unread_for(user)).not_to include @topic
      else
        expect(DiscussionTopic.read_for(user)).not_to include @topic
        expect(DiscussionTopic.unread_for(user)).to include @topic
      end
    end

    before(:once) do
      @topic = @course.discussion_topics.create!(title: "title", message: "message", user: @teacher)
    end

    it "marks a topic you created as read" do
      expect(@topic.read?(@teacher)).to be_truthy
      expect(@topic.unread_count(@teacher)).to eq 0
      check_read_state_scopes read: true, user: @teacher
    end

    it "is unread by default" do
      expect(@topic.read?(@student)).to be_falsey
      expect(@topic.unread_count(@student)).to eq 0
      check_read_state_scopes user: @student
    end

    it "allows being marked unread" do
      @topic.change_read_state("unread", @teacher)
      @topic.reload
      expect(@topic.read?(@teacher)).to be_falsey
      expect(@topic.unread_count(@teacher)).to eq 0
      check_read_state_scopes user: @teacher
    end

    it "allows being marked read" do
      @topic.change_read_state("read", @student)
      @topic.reload
      expect(@topic.read?(@student)).to be_truthy
      expect(@topic.unread_count(@student)).to eq 0
      check_read_state_scopes read: true, user: @student
    end

    it "allows mark all as unread with forced_read_state" do
      @entry = @topic.discussion_entries.create!(message: "Hello!", user: @teacher)
      @reply = @entry.reply_from(user: @student, text: "ohai!")
      @reply.change_read_state("read", @teacher, forced: false)

      @topic.change_all_read_state("unread", @teacher, forced: true)
      @topic.reload
      expect(@topic.read?(@teacher)).to be_falsey

      expect(@entry.read?(@teacher)).to be_falsey
      expect(@entry.find_existing_participant(@teacher)).to be_forced_read_state

      expect(@reply.read?(@teacher)).to be_falsey
      expect(@reply.find_existing_participant(@teacher)).to be_forced_read_state

      expect(@topic.unread_count(@teacher)).to eq 2
      check_read_state_scopes user: @teacher
    end

    it "allows mark all as read without forced_read_state" do
      @entry = @topic.discussion_entries.create!(message: "Hello!", user: @teacher)
      @reply = @entry.reply_from(user: @student, text: "ohai!")
      @reply.change_read_state("unread", @student, forced: true)

      @topic.change_all_read_state("read", @student)
      @topic.reload

      expect(@topic.read?(@student)).to be_truthy

      expect(@entry.read?(@student)).to be_truthy
      expect(@entry.find_existing_participant(@student)).not_to be_forced_read_state

      expect(@reply.read?(@student)).to be_truthy
      expect(@reply.find_existing_participant(@student)).to be_forced_read_state

      expect(@topic.unread_count(@student)).to eq 0
      check_read_state_scopes read: true, user: @student
    end

    it "uses unique_constaint_retry when updating read state" do
      expect(DiscussionTopic).to receive(:unique_constraint_retry).once
      @topic.change_read_state("read", @student)
    end

    it "uses unique_constaint_retry when updating all read state" do
      expect(DiscussionTopic).to receive(:unique_constraint_retry).once
      @topic.change_all_read_state("unread", @student)
    end

    it "syncs unread state with the stream item" do
      @stream_item = @topic.reload_stream_item
      expect(@stream_item.stream_item_instances.detect { |sii| sii.user_id == @teacher.id }).to be_read
      expect(@stream_item.stream_item_instances.detect { |sii| sii.user_id == @student.id }).to be_unread

      @topic.change_all_read_state("unread", @teacher)
      @topic.change_all_read_state("read", @student)
      @topic.reload

      @stream_item = @topic.stream_item
      expect(@stream_item.stream_item_instances.detect { |sii| sii.user_id == @teacher.id }).to be_unread
      expect(@stream_item.stream_item_instances.detect { |sii| sii.user_id == @student.id }).to be_read
    end
  end

  context "subscribing" do
    before :once do
      @context = @course
      discussion_topic_model(user: @teacher)
    end

    it "allows subscription" do
      expect(@topic.subscribed?(@student)).to be_falsey
      @topic.subscribe(@student)
      expect(@topic.subscribed?(@student)).to be_truthy
    end

    it "allows unsubscription" do
      expect(@topic.subscribed?(@teacher)).to be_truthy
      @topic.unsubscribe(@teacher)
      expect(@topic.subscribed?(@teacher)).to be_falsey
    end

    it "is idempotent" do
      expect(@topic.subscribed?(@student)).to be_falsey
      @topic.unsubscribe(@student)
      expect(@topic.subscribed?(@student)).to be_falsey
    end

    it "assumes the author is subscribed" do
      expect(@topic.subscribed?(@teacher)).to be_truthy
    end

    it "assumes posters are subscribed" do
      @topic.reply_from(user: @student, text: "first post!")
      expect(@topic.subscribed?(@student)).to be_truthy
    end

    context "when initial_post_required" do
      it "unsubscribes a user when all of their posts are deleted" do
        @topic.require_initial_post = true
        @topic.save!
        @entry = @topic.reply_from(user: @student, text: "first post!")
        expect(@topic.subscribed?(@student)).to be_truthy
        @entry.destroy
        expect(@topic.subscribed?(@student)).to be_falsey
      end
    end
  end

  context "subscription holds" do
    before :once do
      @context = @course
    end

    it "holds when requiring an initial post" do
      discussion_topic_model(user: @teacher, require_initial_post: true)
      expect(@topic.subscription_hold(@student, nil)).to eq :initial_post_required
    end

    it "holds when the user is not in a group set" do
      # i.e. when you check holds on a root topic and no child topics are for groups
      # the user is in
      group_discussion_assignment
      expect(@topic.subscription_hold(@student, nil)).to eq :not_in_group_set
    end

    it "does not fail for group discussion" do
      group = group_model(name: "Project Group 1", group_category: @group_category, context: @course)
      topic = group.discussion_topics.create!(title: "hi", message: "hey")
      expect(topic.subscription_hold(@student, nil)).to eq :not_in_group
      expect(topic.child_topic_for(@student)).to be_nil
    end

    it "holds when the user is not in a group" do
      group_discussion_assignment
      expect(@topic.child_topics.first.subscription_hold(@student, nil)).to eq :not_in_group
    end

    it "handles nil user case" do
      group_discussion_assignment
      expect(@topic.child_topics.first.subscription_hold(nil, nil)).to be_nil
    end

    it "does not subscribe the author if there is a hold" do
      group_discussion_assignment
      @topic.user = @teacher
      @topic.save!
      expect(@topic.subscription_hold(@teacher, nil)).to eq :not_in_group_set
      expect(@topic.subscribed?(@teacher)).to be_falsey
    end

    it "sets the topic participant subscribed field to false when there is a hold" do
      teacher_in_course(active_all: true)
      group_discussion_assignment
      group_discussion = @topic.child_topics.first
      group_discussion.user = @teacher
      group_discussion.save!
      group_discussion.change_read_state("read", @teacher) # quick way to make a participant
      expect(group_discussion.discussion_topic_participants.where(user_id: @teacher.id).first.subscribed).to be false
    end
  end

  context "a group topic subscription" do
    before(:once) do
      group_discussion_assignment
    end

    it "returns true if the user is subscribed to a child topic" do
      @topic.child_topics.first.subscribe(@student)
      expect(@topic.child_topics.first.subscribed?(@student)).to be_truthy
      expect(@topic.subscribed?(@student)).to be_truthy
    end

    it "returns true if the user has posted to a child topic" do
      child_topic = @topic.child_topics.first
      child_topic.context.add_user(@student)
      child_topic.reply_from(user: @student, text: "post")
      child_topic_participant = child_topic.update_or_create_participant(current_user: @student, subscribed: nil)
      expect(child_topic_participant.subscribed).to be_nil
      expect(@topic.subscribed?(@student)).to be_truthy
    end

    it "subscribes a group user to the child topic" do
      child_one, child_two = @topic.child_topics
      child_one.context.add_user(@student)
      @topic.subscribe(@student)

      expect(child_one.subscribed?(@student)).to be_truthy
      expect(child_two.subscribed?(@student)).not_to be_truthy
      expect(@topic.subscribed?(@student)).to be_truthy
    end

    it "unsubscribes a group user from the child topic" do
      child_one, child_two = @topic.child_topics
      child_one.context.add_user(@student)
      @topic.subscribe(@student)
      @topic.unsubscribe(@student)

      expect(child_one.subscribed?(@student)).not_to be_truthy
      expect(child_two.subscribed?(@student)).not_to be_truthy
      expect(@topic.subscribed?(@student)).not_to be_truthy
    end
  end

  context "materialized view" do
    before :once do
      topic_with_nested_replies
    end

    around do |example|
      # materialized view jobs are now delayed
      Timecop.freeze(20.seconds.from_now, &example)
    end

    it "returns nil if the view has not been built yet, and schedule a job" do
      DiscussionTopic::MaterializedView.for(@topic).destroy
      expect(@topic.materialized_view).to be_nil
      expect(@topic.materialized_view).to be_nil
      expect(Delayed::Job.where(singleton: "materialized_discussion:#{@topic.id}").count).to eq 1
    end

    it "returns the materialized view if it's up to date" do
      run_jobs
      view = DiscussionTopic::MaterializedView.where(discussion_topic_id: @topic).first
      expect(@topic.materialized_view).to eq [view.json_structure, view.participants_array, view.entry_ids_array, []]
    end

    it "updates the materialized view on new entry" do
      run_jobs
      expect(Delayed::Job.where(singleton: "materialized_discussion:#{@topic.id}").count).to eq 0
      @topic.reply_from(user: @user, text: "ohai")
      expect(Delayed::Job.where(singleton: "materialized_discussion:#{@topic.id}").count).to eq 1
    end

    it "updates the materialized view on edited entry" do
      reply = @topic.reply_from(user: @user, text: "ohai")
      run_jobs
      expect(Delayed::Job.where(singleton: "materialized_discussion:#{@topic.id}").count).to eq 0
      reply.update(message: "i got that wrong before")
      expect(Delayed::Job.where(singleton: "materialized_discussion:#{@topic.id}").count).to eq 1
    end

    it "returns empty data for a materialized view on a new (unsaved) topic" do
      new_topic = DiscussionTopic.new(context: @topic.context, discussion_type: DiscussionTopic::DiscussionTypes::NOT_THREADED)
      expect(new_topic).to be_new_record
      expect(new_topic.materialized_view).to eq ["[]", [], [], []]
      expect(Delayed::Job.where(singleton: "materialized_discussion:#{new_topic.id}").count).to eq 0
    end
  end

  context "destroy" do
    before(:once) { group_discussion_assignment }

    it "destroys the assignment and associated child topics" do
      @topic.destroy
      expect(@topic.reload).to be_deleted
      @topic.child_topics.each { |ct| expect(ct.reload).to be_deleted }
      expect(@assignment.reload).to be_deleted
    end

    it "does not revive the assignment if updated when deleted" do
      @topic.destroy
      expect(@assignment.reload).to be_deleted
      @topic.touch
      expect(@assignment.reload).to be_deleted
    end
  end

  context "restore" do
    it "restores the assignment and associated child topics" do
      group_discussion_assignment
      @topic.destroy

      expect(@topic.reload.assignment).to receive(:restore).with(:discussion_topic).once
      @topic.restore
      expect(@topic.reload).to be_unpublished
      @topic.child_topics.each { |ct| expect(ct.reload).to be_unpublished }
      expect(@topic.assignment).to be_unpublished
    end

    it "restores an announcement to active state" do
      ann = @course.announcements.create!(title: "something", message: "somethingelse")
      ann.destroy

      ann.restore
      expect(ann.reload).to be_active
    end

    it "restores an announcement to active state with sections" do
      section = @course.course_sections.create!
      @course.save!
      announcement = Announcement.create!(
        title: "some topic",
        message: "I announce that i am lying",
        user: @teacher,
        context: @course,
        workflow_state: "published"
      )
      add_section_to_topic(announcement, section)
      announcement.save!
      announcement.destroy

      announcement.restore
      expect(announcement.reload).to be_active
    end

    it "restores a topic with submissions to active state" do
      discussion_topic_model(context: @course)
      @topic.reply_from(user: @student, text: "huttah!")
      @topic.destroy

      @topic.restore
      expect(@topic.reload).to be_active
    end

    it "does not allow restoring child discussion when the parent is destroyed" do
      group_discussion_assignment
      @topic.destroy

      child = @topic.child_topics.first

      expect(child.restore).to be false
      expect(child.deleted?).to be true
      expect(child.errors[:deleted_at]).to be_present
    end
  end

  context "restorable?" do
    it "returns true for basic discussions" do
      group_assignment_discussion

      expect(@root_topic.restorable?).to be(true)
      expect(@topic.restorable?).to be(true)
    end

    it "returns true for deleted root_topics" do
      group_assignment_discussion

      @root_topic.destroy
      expect(@root_topic.restorable?).to be(true)
    end

    it "returns false for deleted child_topics when the root topic is deleted" do
      group_assignment_discussion

      @root_topic.destroy
      expect(@topic.reload.restorable?).to be(false)
    end

    it "returns true for deleted_child topics when the root topic is not deleted" do
      group_assignment_discussion
      @topic.destroy
      expect(@topic.restorable?).to be(true)
    end
  end

  describe "reply_from" do
    before(:once) do
      @topic = @course.discussion_topics.create!(user: @teacher, message: "topic")
    end

    it "ignores responses in deleted account" do
      account = Account.create!
      @teacher = course_with_teacher(active_all: true, account:).user
      @context = @course
      discussion_topic_model(user: @teacher)
      account.destroy
      expect { @topic.reload.reply_from(user: @teacher, text: "entry") }.to raise_error(IncomingMail::Errors::UnknownAddress)
    end

    it "prefers html to text" do
      discussion_topic_model
      msg = @topic.reply_from(user: @teacher, text: "text body", html: "<p>html body</p>")
      expect(msg).not_to be_nil
      expect(msg.message).to eq "<p>html body</p>"
    end

    it "does not allow replies from students to locked topics" do
      course_with_teacher(active_all: true)
      discussion_topic_model(context: @course)
      @topic.lock!
      @topic.reply_from(user: @teacher, text: "reply") # should not raise error
      student_in_course(course: @course).accept!
      expect { @topic.reply_from(user: @student, text: "reply") }.to raise_error(IncomingMail::Errors::ReplyToLockedTopic)
    end

    it "does not allow replies from students to announcements that are closed for comments" do
      announcement = @course.announcements.create!(message: "Lock this")
      expect(announcement.comments_disabled?).to be_falsey
      @course.lock_all_announcements = true
      @course.save!
      expect(announcement.reload.comments_disabled?).to be_truthy
      expect { announcement.reply_from(user: @student, text: "reply") }.to raise_error(IncomingMail::Errors::ReplyToLockedTopic)
    end

    it "does not allow replies to locked announcements" do
      announcement = @course.announcements.create!(message: "Lock this")
      announcement.locked = true
      announcement.save!
      expect { announcement.reply_from(user: @student, text: "reply") }.to raise_error(IncomingMail::Errors::ReplyToLockedTopic)
    end

    it "does not allow replies from students to discussion topic before unlock date" do
      @topic = @course.discussion_topics.create!(user: @teacher)
      @topic.update_attribute(:delayed_post_at, 1.day.from_now)
      expect { @topic.reply_from(user: @student, text: "reply") }.to raise_error(IncomingMail::Errors::ReplyToLockedTopic)
    end

    it "does not allow replies from students to discussion topic after lock date" do
      @topic = @course.discussion_topics.create!(user: @teacher)
      @topic.update_attribute(:lock_at, 1.day.ago)
      expect { @topic.reply_from(user: @student, text: "reply") }.to raise_error(IncomingMail::Errors::ReplyToLockedTopic)
    end

    it "reflects course setting for when lock_all_announcements is enabled" do
      announcement = @course.announcements.create!(message: "Lock this")
      expect(announcement.comments_disabled?).to be_falsey
      @course.lock_all_announcements = true
      @course.save!
      expect(announcement.reload.comments_disabled?).to be_truthy
    end

    it "reflects account setting for when lock_all_announcements is enabled" do
      announcement = @course.announcements.create!(message: "Lock this")
      expect(announcement.comments_disabled?).to be_falsey
      @course.account.tap do |a|
        a.settings[:lock_all_announcements] = { value: true, locked: true }
        a.save!
      end
      expect(announcement.reload.comments_disabled?).to be_truthy
    end

    it "does not allow replies from students to topics locked based on date" do
      course_with_teacher(active_all: true)
      discussion_topic_model(context: @course)
      @topic.delayed_post_at = 1.day.from_now
      @topic.save!
      @topic.reply_from(user: @teacher, text: "reply") # should not raise error
      student_in_course(course: @course).accept!
      expect { @topic.reply_from(user: @student, text: "reply") }.to raise_error(IncomingMail::Errors::ReplyToLockedTopic)
    end

    it "returns entry for valid arguments" do
      val = @topic.reply_from(user: @teacher, text: "entry 1")
      expect(val).to be_a DiscussionEntry
    end

    it "raises InvalidParticipant for invalid participants" do
      u = user_with_pseudonym(active_user: true, username: "test1@example.com", password: "test1234")
      expect { @topic.reply_from(user: u, text: "entry 1") }.to raise_error IncomingMail::Errors::InvalidParticipant
    end
  end

  describe "update_order" do
    it "handles existing null positions" do
      topics = (1..4).map { discussion_topic_model(pinned: true) }
      topics.each do |x|
        x.position = nil
        x.save
      end

      new_order = [2, 3, 4, 1]
      ids = new_order.map { |x| topics[x - 1].id }
      topics[0].update_order(ids)
      expect(topics.first.list_scope.map(&:id)).to eq ids
    end
  end

  describe "section specific announcements" do
    before :once do
      @course = course_factory({ course_name: "Course 1", active_all: true })
      @section = @course.course_sections.create!
      @course.save!
      @announcement = Announcement.create!(
        title: "some topic",
        message: "I announce that i am lying",
        user: @teacher,
        context: @course,
        workflow_state: "published"
      )
    end

    def course_with_two_sections
      course = course_factory({ course_name: "Course 1", active_all: true })
      course.course_sections.create!
      course.course_sections.create!
      course.save!
      course
    end

    def basic_announcement_model(opts = {})
      opts.reverse_merge!({
                            title: "Default title",
                            message: "Default message",
                            is_section_specific: false
                          })
      announcement = Announcement.create!(
        title: opts[:title],
        message: opts[:message],
        user: @teacher,
        context: opts[:course],
        workflow_state: "published"
      )
      announcement.is_section_specific = opts[:is_section_specific]
      announcement
    end

    it "only section specific topics can have sections" do
      announcement = basic_announcement_model(course: @course)
      add_section_to_topic(announcement, @section)
      expect(announcement.valid?).to be true
      announcement.is_section_specific = false
      expect(announcement.valid?).to be false
      announcement.discussion_topic_section_visibilities.first.destroy
      expect(announcement.valid?).to be true
    end

    it "section specific topics must have sections" do
      @announcement.is_section_specific = true
      expect(@announcement.valid?).to be false
      errors = @announcement.errors[:is_section_specific]
      expect(errors).to eq ["Section specific topics must have sections"]
    end

    it "returns the sections for the address_book_context relative to the student" do
      topic = DiscussionTopic.create!(title: "some title", context: @course, user: @teacher)
      section2 = @course.course_sections.create!(name: "no students")
      user = student_in_course(course: @course, active_enrollment: true, section: @section).user
      add_section_to_topic(topic, @section)
      add_section_to_topic(topic, section2)
      expect(topic.address_book_context_for(user).to_a).to eq [@section]
    end

    context "differentiated modules address_book_context_for" do
      before do
        @topic = discussion_topic_model(user: @teacher, context: @course)
        @topic.update!(only_visible_to_overrides: true)
        @course_section = @course.course_sections.create
        @student1 = student_in_course(course: @course, active_enrollment: true).user
        @student2 = student_in_course(course: @course, active_enrollment: true, section: @course_section).user
        @teacher1 = teacher_in_course(course: @course, active_enrollment: true).user
      end

      it "returns the section for the address_book_context relative to the student with differentiated modules enabled" do
        @topic.assignment_overrides.create!(set: @course_section)

        expect(@topic.address_book_context_for(@teacher1).to_a).to eq [@course_section]
      end

      it "returns the course if there are student overrides" do
        override = @topic.assignment_overrides.create!
        override.assignment_override_students.create!(user: @student1)

        expect(@topic.address_book_context_for(@teacher1)).to eq @course
      end
    end

    it "returns no sections for the address_book_context when student has none" do
      topic = DiscussionTopic.create!(title: "some title", context: @course, user: @teacher)
      section2 = @course.course_sections.create!(name: "no topics")
      user = student_in_course(course: @course, active_enrollment: true, section: section2).user
      add_section_to_topic(topic, @section)
      expect(topic.address_book_context_for(user).to_a).to eq []
    end

    it "returns all sections for the address_book_context when student has 2" do
      topic = DiscussionTopic.create!(title: "some title", context: @course, user: @teacher)
      section2 = @course.course_sections.create!(name: "no topics")
      user = student_in_course(course: @course, active_enrollment: true, section: @section).user
      @course.enroll_student(user, allow_multiple_enrollments: true, section: section2, enrollment_state: "active")
      add_section_to_topic(topic, @section)
      add_section_to_topic(topic, section2)
      expect(topic.address_book_context_for(user).to_a.sort).to eq [@section, section2].sort
    end

    it "group topics cannot be section specific" do
      group_category = @course.group_categories.create(name: "new category")
      @group = @course.groups.create(name: "group", group_category:)
      student_in_course(active_all: true)
      @group.add_user(@student)
      announcement = basic_announcement_model(course: @group)
      add_section_to_topic(announcement, @section)
      expect(announcement.valid?).to be false
      errors = announcement.errors[:is_section_specific]
      # NOTE: the feature flag validation will also fail here, but we still want this
      # validation to trigger too.
      expect(errors.include?("Only course announcements and discussions can be section-specific")).to be true
    end

    it "allows discussions to be section-specific if the feature is enabled" do
      topic = DiscussionTopic.create!(title: "some title",
                                      context: @course,
                                      user: @teacher)
      add_section_to_topic(topic, @section)
      expect(topic.valid?).to be true
    end

    it "does not allow graded discussions to be section-specific" do
      group_discussion_assignment
      add_section_to_topic(@topic, @section)
      expect(@topic.valid?).to be false
    end

    it "does not allow course grouped discussions to be section-specific" do
      group_discussion_topic_model
      add_section_to_topic(@group_topic, @section)
      expect(@group_topic.valid?).to be false
    end

    it "does not include deleted sections" do
      course = course_with_two_sections
      announcement = basic_announcement_model(
        course:
      )
      add_section_to_topic(announcement, course.course_sections.first)
      add_section_to_topic(announcement, course.course_sections.second)
      announcement.save!
      expect(announcement.course_sections.length).to eq 2
      course.course_sections.second.reload
      course.course_sections.second.destroy
      announcement.reload
      expect(announcement.course_sections.length).to eq 1
      expect(announcement.course_sections.first.id).to eq course.course_sections.first.id
    end

    it "allows deletion of announcement" do
      course = course_with_two_sections
      announcement = basic_announcement_model(
        course:,
        is_section_specific: true
      )
      add_section_to_topic(announcement, course.course_sections.first)
      add_section_to_topic(announcement, course.course_sections.second)
      announcement.save!
      Announcement.find(announcement.id).destroy
      announcement.reload
      expect(announcement.workflow_state).to eq "deleted"
    end

    it "scope allows non-section-specific announcements" do
      course = course_with_two_sections
      announcement = basic_announcement_model(
        course:,
        is_section_specific: false
      )
      announcement.save!
      topics = DiscussionTopic.in_sections(course.course_sections)
      expect(topics.length).to eq 1
    end

    it "scope allows section-specific announcements if in right section" do
      course = course_with_two_sections
      announcement = basic_announcement_model(
        course:
      )
      add_section_to_topic(announcement, course.course_sections.first)
      announcement.save!
      topics = DiscussionTopic.in_sections(course.course_sections)
      expect(topics.length).to eq 1
    end

    it "scope forbids section-specific announcements if in wrong section" do
      course = course_with_two_sections
      announcement = basic_announcement_model(
        course:
      )
      add_section_to_topic(announcement, course.course_sections.second)
      announcement.save!
      topics = DiscussionTopic.in_sections([course.course_sections.first])
      expect(topics.length).to eq 0
    end

    it "scope forbids sections from multiple courses" do
      course1 = course_with_two_sections
      course2 = course_with_two_sections
      sections = [course1.course_sections.first, course2.course_sections.first]
      expect { DiscussionTopic.in_sections(sections) }
        .to raise_error(DiscussionTopic::QueryError,
                        "Searching for announcements in sections must span exactly one course")
    end

    it "don't return duplicates if matched multiple sections" do
      course = course_with_two_sections
      announcement = basic_announcement_model(
        course:
      )
      add_section_to_topic(announcement, course.course_sections.first)
      add_section_to_topic(announcement, course.course_sections.second)
      announcement.save!
      topics = DiscussionTopic.in_sections(
        [course.course_sections.first, course.course_sections.second]
      )
      expect(topics.length).to eq 1
    end
  end

  describe "context_module_action" do
    context "group discussion" do
      before :once do
        group_assignment_discussion(course: @course)
        @module = @course.context_modules.create!
        @topic_tag = @module.add_item(type: "discussion_topic", id: @root_topic.id)
        @module.completion_requirements = { @topic_tag.id => { type: "must_contribute" } }
        @module.save!
        student_in_course active_all: true
        @group.add_user @student, "accepted"
      end

      it "fulfills module completion requirements on the root topic" do
        @topic.reply_from(user: @student, text: "huttah!")
        expect(@student.context_module_progressions.where(context_module_id: @module).first.requirements_met).to include({ id: @topic_tag.id, type: "must_contribute" })
      end
    end
  end

  describe "context modules" do
    before(:once) do
      discussion_topic_model(context: @course)
      @module = @course.context_modules.create!(name: "some module")
      @tag = @module.add_item(type: "discussion_topic", id: @topic.id)
      @module.save!
      @topic.reload
    end

    it "clears stream items when unpublishing a module" do
      expect { @module.unpublish! }.to change { @student.stream_item_instances.count }.by(-1)
    end

    it "removes stream items when the module item is changed to unpublished" do
      expect { @tag.unpublish! }.to change { @student.stream_item_instances.count }.by(-1)
    end

    it "clears stream items when added to unpublished module items" do
      expect do
        @module.content_tags.create!(workflow_state: "unpublished", content: @topic, context: @course)
      end.to change { @student.stream_item_instances.count }.by(-1)
    end

    describe "unpublished context module" do
      before(:once) do
        @module.unpublish!
        @tag.unpublish!
      end

      it "does not create stream items for unpublished modules" do
        @topic.unpublish!
        expect { @topic.publish! }.not_to change { @student.stream_item_instances.count }
      end

      it "removes stream items from published topic when added to an unpublished module" do
        topic = discussion_topic_model(context: @course)
        expect { @module.add_item(type: "discussion_topic", id: topic.id) }.to change { @student.stream_item_instances.count }.by(-1)
      end

      it "creates stream items when module is published" do
        @tag.publish!
        expect { @module.publish! }.to change { @student.stream_item_instances.count }.by 1
      end

      it "creates stream items when module item is published" do
        @module.publish!
        expect { @tag.publish! }.to change { @student.stream_item_instances.count }.by 1
      end
    end
  end

  describe "entries_for_feed" do
    before(:once) do
      @topic = @course.discussion_topics.create!(user: @teacher, message: "topic")
      @entry1 = @topic.discussion_entries.create!(user: @teacher, message: "hi from teacher")
      @entry2 = @topic.discussion_entries.create!(user: @student, message: "hi")
    end

    it "returns active entries by default" do
      expect(@topic.entries_for_feed(@student)).to_not be_empty
    end

    it "returns empty if user cannot see posts" do
      expect(@topic.entries_for_feed(nil)).to be_empty
    end

    it "returns empty if the topic is locked for the user" do
      @topic.lock!
      expect(@topic.entries_for_feed(@student)).to be_empty
    end

    it "returns student entries if specified" do
      @topic.update(podcast_has_student_posts: true)
      expect(@topic.entries_for_feed(@student, true)).to match_array([@entry1, @entry2])
    end

    it "only returns admin entries if specified" do
      @topic.update(podcast_has_student_posts: false)
      expect(@topic.entries_for_feed(@student, true)).to match_array([@entry1])
    end

    it "returns student entries for group discussions even if not specified" do
      group_category
      group_with_user(group_category: @group_category, user: @student)
      @topic = @group.discussion_topics.create(title: "group topic", user: @teacher)
      @topic.discussion_entries.create(message: "some message", user: @student)
      @topic.update(podcast_has_student_posts: false)
      expect(@topic.entries_for_feed(@student, true)).to_not be_empty
    end
  end

  describe "to_podcast" do
    it "includes media extension in enclosure url even though it is a redirect (for itunes)" do
      @topic = @course.discussion_topics.create!(
        user: @teacher,
        message: "topic"
      )
      attachment_model(context: @course, filename: "test.mp4", content_type: "video")
      @attachment.podcast_associated_asset = @topic

      rss = DiscussionTopic.to_podcast([@attachment])
      expect(rss.first.enclosure.url).to match(/download.mp4/)
    end
  end

  context "announcements" do
    context "scopes" do
      context "by_posted_at" do
        let(:c) { Course.create! }
        let(:new_ann) do
          lambda do
            Announcement.create!({
                                   context: c,
                                   message: "Test Message",
                                 })
          end
        end

        it "properly sorts collections by delayed_post_at and posted_at" do
          anns = Array.new(10) do |i|
            ann = new_ann.call
            setter = [:delayed_post_at=, :posted_at=][i % 2]
            ann.send(setter, i.days.ago)
            ann.position = 1
            ann.save!
            ann
          end
          expect(c.announcements.by_posted_at).to eq(anns)
        end
      end
    end
  end

  context "notifications" do
    before :once do
      user_with_pseudonym(active_all: true)
      course_with_teacher(user: @user, active_enrollment: true)
      n = Notification.create!(name: "New Discussion Topic", category: "TestImmediately")
      NotificationPolicy.create!(notification: n, communication_channel: @user.communication_channel, frequency: "immediately")
    end

    it "sends a message for a published course" do
      @course.offer!
      topic = @course.discussion_topics.create!(title: "title")
      expect(topic.messages_sent["New Discussion Topic"].map(&:user)).to include(@user)
      expect(topic.messages_sent["New Discussion Topic"].first.from_name).to eq @course.name
    end

    it "does not send a message for an unpublished course" do
      topic = @course.discussion_topics.create!(title: "title")
      expect(topic.messages_sent["New Discussion Topic"]).to be_blank
    end

    context "group discussions" do
      before :once do
        group_model(context: @course)
        @group.add_user(@user)
      end

      it "sends a message for a group discussion in a published course" do
        @course.offer!
        topic = @group.discussion_topics.create!(title: "title")
        expect(topic.messages_sent["New Discussion Topic"].map(&:user)).to include(@user)
      end

      it "does not send a message for a group discussion in an unpublished course" do
        topic = @group.discussion_topics.create!(title: "title")
        expect(topic.messages_sent["New Discussion Topic"]).to be_blank
      end
    end
  end

  it "lets course admins reply to concluded topics" do
    course_with_teacher(active_all: true)
    topic = @course.discussion_topics.create!
    group_model(context: @course)
    group_topic = @group.discussion_topics.create!
    @course.complete!
    expect(topic.grants_right?(@teacher, :reply)).to be_truthy
    expect(group_topic.grants_right?(@teacher, :reply)).to be_truthy
  end

  describe "duplicating topics" do
    before :once do
      course_with_teacher(active_all: true)
      student_in_course(active_all: true)
      @course_section1 = @course.course_sections.create!
      @course_section2 = @course.course_sections.create!
    end

    it "without custom opts" do
      group_discussion_assignment # Discussion has title "topic"
      @topic.podcast_has_student_posts = true
      new_topic = @topic.duplicate({ user: @teacher })
      expect(new_topic.title).to eql "topic Copy"
      expect(new_topic.assignment).not_to be_nil
      expect(new_topic.assignment.new_record?).to be true
      expect(new_topic.podcast_has_student_posts).to be true
      # Child topics don't get duplicated.  The hooks create those for us
      expect(new_topic.child_topics.length).to eq 0
      new_topic.save!
      # Verify that saving indeed created the appropriate child topics
      new_topic = DiscussionTopic.find(new_topic.id)
      expect(new_topic.child_topics.length).not_to eq 0
    end

    it "respect provided title" do
      discussion_topic_model({ title: "not foobar" })
      @topic.save! # only saved topics can be duplicated
      new_topic = @topic.duplicate({ copy_title: "foobar" })
      expect(new_topic.title).to eql "foobar"
    end

    it "respect provided user" do
      discussion_topic_model
      @topic.save!
      new_topic = @topic.duplicate({ user: @student })
      expect(new_topic.user_id).to eq @student.id
    end

    it "duplicates sections" do
      discussion_topic_model(context: @course)
      @topic.is_section_specific = true
      @topic.course_sections = [@course_section1, @course_section2]
      @topic.save!
      new_topic = @topic.duplicate
      expect(new_topic.discussion_topic_section_visibilities.length).to eq 2
      new_course_sections = new_topic.discussion_topic_section_visibilities.to_set(&:course_section_id)
      expect(new_course_sections).to eq [@course_section1.id, @course_section2.id].to_set
      expect(new_topic).to be_valid
    end

    it "does not duplicate deleted visibilities" do
      discussion_topic_model(context: @course)
      @topic.is_section_specific = true
      @topic.course_sections = [@course_section1, @course_section2]
      @topic.discussion_topic_section_visibilities.second.destroy!
      @topic.save!
      new_topic = @topic.duplicate
      expect(new_topic.discussion_topic_section_visibilities.length).to eq 1
      expect(new_topic.discussion_topic_section_visibilities.first.course_section_id).to eq @course_section1.id
      expect(new_topic).to be_valid
    end
  end

  describe "users with permissions" do
    before :once do
      @course = course_factory(active_all: true)
      @section1 = @course.course_sections.create!
      @section2 = @course.course_sections.create!
      @limited_teacher = create_enrolled_user(@course,
                                              @section1,
                                              name: "limited teacher",
                                              enrollment_type: "TeacherEnrollment",
                                              limit_privileges_to_course_section: true)
      @student1 = create_enrolled_user(@course, @section1, name: "student 1", enrollment_type: "StudentEnrollment")
      @student2 = create_enrolled_user(@course, @section2, name: "student 2", enrollment_type: "StudentEnrollment")
      @all_users = [@teacher, @limited_teacher, @student1, @student2]
    end

    it "non-specific-topic is visible to everyone" do
      topic = @course.discussion_topics.create!(title: "foo",
                                                message: "bar",
                                                workflow_state: "published")
      users = topic.users_with_permissions(@all_users)
      expect(users.to_set(&:id)).to eq(@all_users.to_set(&:id))
    end

    it "specific topic limits properly" do
      topic = DiscussionTopic.new(title: "foo",
                                  message: "bar",
                                  context: @course,
                                  user: @teacher)
      add_section_to_topic(topic, @section2)
      topic.save!
      users = topic.users_with_permissions(@all_users)
      expect(users.to_set(&:id)).to eq([@teacher.id, @student2.id].to_set)
    end
  end

  describe "course with multiple sections" do
    before :once do
      @course = course_factory(active_all: true)
      @section1 = @course.course_sections.create!(name: "Section 1")
      @section2 = @course.course_sections.create!(name: "Section 2")

      @student1 = create_enrolled_user(@course, @section2, name: "Student 1", enrollment_type: "StudentEnrollment")
      @student2 = create_enrolled_user(@course, @section2, name: "Student 2", enrollment_type: "StudentEnrollment")

      @student1.enrollments.first.conclude

      @all_users = [@teacher, @student1, @student2]
    end

    it "section specific topic.users_with_permissions does not show completed enrollments" do
      topic = DiscussionTopic.new(title: "foo",
                                  message: "bar",
                                  context: @course,
                                  user: @teacher)
      add_section_to_topic(topic, @section2)
      topic.save!

      users = topic.users_with_permissions(@all_users)

      expect(users.count).to eq(2)
      expect(users.to_set(&:id)).to eq([@teacher.id, @student2.id].to_set)
    end
  end

  context "only_graders_can_rate" do
    it "checks permissions on the course level for group level discussions" do
      group = @course.groups.create!
      topic = group.discussion_topics.create!(allow_rating: true, only_graders_can_rate: true)
      expect(topic.grants_right?(@teacher, :rate)).to be true
    end
  end

  describe "create" do
    it "sets the root_account_id using context" do
      discussion_topic_model(context: @course)
      expect(@topic.root_account_id).to eq @course.root_account_id
    end
  end

  describe "#anonymous?" do
    let(:discussion) { discussion_topic_model(context: @course) }

    context "anonymous_state is nil" do
      it "returns false" do
        expect(discussion.anonymous?).to be false
      end
    end

    context "anonymous_state is not nil" do
      before do
        discussion.update(anonymous_state: "full_anonymity")
      end

      it "returns true" do
        expect(discussion.anonymous?).to be true
      end
    end
  end

  describe "#update_assignment" do
    context "with course paces" do
      before do
        discussion_topic_model(context: @course)
        @course.enable_course_paces = true
        @course.save!
        @course_pace = course_pace_model(course: @course)
        @module = @course.context_modules.create!(name: "some module")
        @tag = @module.add_item(type: "discussion_topic", id: @topic.id)
        @module.save!
        @topic.reload
        # Reset progresses to verify progresses are added during tests
        Progress.destroy_all
      end

      it "runs update_course_pace_module_items on content tags when an assignment is created" do
        expect(Progress.last).to be_nil
        @topic.assignment = @course.assignments.create!(title: "some assignment")
        @topic.save!
        expect(Progress.last.context).to eq(@course_pace)
      end

      it "runs update_course_pace_module_items on content tags when an assignment is removed" do
        expect(Progress.last).to be_nil
        @topic.assignment = @course.assignments.create!(title: "some assignment")
        @topic.save!
        expect(Progress.last.context).to eq(@course_pace)
        Progress.last.destroy
        @topic.old_assignment_id = @topic.assignment_id
        @topic.assignment_id = nil
        @topic.save!
        expect(Progress.last.context).to eq(@course_pace)
      end
    end
  end

  describe "checkpoints" do
    before do
      @course.account.enable_feature!(:discussion_checkpoints)
      @topic = DiscussionTopic.create_graded_topic!(course: @course, title: "Discussion Topic Title", user: @teacher)
    end

    it "not in place in the topic" do
      expect(@topic.checkpoints?).to be false
      expect(@topic.sub_assignments.length).to eq 0
      expect(@topic.reply_to_topic_checkpoint).to be_nil
      expect(@topic.reply_to_entry_checkpoint).to be_nil
      expect(@topic.reply_to_entry_required_count).to eq 0
    end

    it "does not allow setting the reply_to_entry_required_count to more than 10" do
      expect do
        @topic.create_checkpoints(reply_to_topic_points: 10, reply_to_entry_points: 15, reply_to_entry_required_count: 11)
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "does not create a discussion topic per-checkpoint (instead, checkpoints belong to the topic through the parent)" do
      expect do
        @topic.create_checkpoints(reply_to_topic_points: 10, reply_to_entry_points: 15, reply_to_entry_required_count: 0)
      end.not_to change { DiscussionTopic.count }.from(1)
    end

    describe "in place" do
      before do
        @course.account.enable_feature!(:discussion_checkpoints)
        @topic.reload
        @topic.create_checkpoints(reply_to_topic_points: 10, reply_to_entry_points: 15, reply_to_entry_required_count: 5)
      end

      it "in the topic" do
        expect(@topic.checkpoints?).to be true
        expect(@topic.sub_assignments.length).to eq 2
        expect(@topic.reply_to_topic_checkpoint.sub_assignment_tag).to eq CheckpointLabels::REPLY_TO_TOPIC
        expect(@topic.reply_to_entry_checkpoint.sub_assignment_tag).to eq CheckpointLabels::REPLY_TO_ENTRY
      end

      it "correctly marks the reply to topic checkpoint submission as submitted when the student replies to topic" do
        @topic.discussion_entries.create!(user: @student, message: "reply to topic")

        expect(@topic.assignment.submissions.find_by(user: @student).workflow_state).to eq "unsubmitted"
        expect(@topic.reply_to_topic_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "submitted"
        expect(@topic.reply_to_entry_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "unsubmitted"
      end

      it "correctly marks the reply to entry checkpoint submission as submitted when the student replies to an entry 5 times" do
        entry = @topic.discussion_entries.create!(user: @teacher, message: "reply to topic")
        5.times do
          @topic.discussion_entries.create!(user: @student, message: "reply to entry", root_entry_id: entry.id, parent_id: entry.id)
        end

        expect(@topic.assignment.submissions.find_by(user: @student).workflow_state).to eq "unsubmitted"
        expect(@topic.reply_to_topic_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "unsubmitted"
        expect(@topic.reply_to_entry_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "submitted"
      end

      it "correctly leaves the reply to entry checkpoint submission as unsubmitted when the student has not replied to an entry 5 times" do
        entry = @topic.discussion_entries.create!(user: @teacher, message: "reply to topic")
        @topic.discussion_entries.create!(user: @student, message: "reply to topic by student")
        @topic.discussion_entries.create!(user: @student, message: "reply to entry", root_entry_id: entry.id, parent_id: entry.id)

        expect(@topic.assignment.submissions.find_by(user: @student).workflow_state).to eq "unsubmitted"
        expect(@topic.reply_to_topic_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "submitted"
        expect(@topic.reply_to_entry_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "unsubmitted"
      end

      it "correctly marks both checkpoint submissions when the user replies to both topic and entry 5 times" do
        entry_by_teacher = @topic.discussion_entries.create!(user: @teacher, message: "reply to topic by teacher")
        @topic.discussion_entries.create!(user: @student, message: "reply to topic by student")
        5.times do
          @topic.discussion_entries.create!(user: @student, message: "reply to entry by student", root_entry_id: entry_by_teacher.id, parent_id: entry_by_teacher.id)
        end

        expect(@topic.assignment.submissions.find_by(user: @student).workflow_state).to eq "submitted"
        expect(@topic.reply_to_topic_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "submitted"
        expect(@topic.reply_to_entry_checkpoint.submissions.find_by(user: @student).workflow_state).to eq "submitted"
      end

      it "has the correct reply_to_entry_required_count and is valid" do
        expect(@topic.reply_to_entry_required_count).to eq 5
        expect(@topic).to be_valid
      end
    end
  end

  describe "unlock_at and delayed_post_at" do
    before do
      @topic = @course.discussion_topics.create!(title: "topic", user: @teacher)
    end

    it "prefers unlock_at to delayed_post_at" do
      @topic[:delayed_post_at] = 5.days.from_now
      @topic[:unlock_at] = Time.zone.now
      expect(@topic.delayed_post_at).to equal @topic[:unlock_at]
      expect(@topic.unlock_at).to equal @topic[:unlock_at]
    end

    it "defaults to delayed_post_at if unlock_at is nil" do
      @topic[:delayed_post_at] = 5.days.from_now
      @topic[:unlock_at] = nil
      expect(@topic.delayed_post_at).to equal @topic[:delayed_post_at]
      expect(@topic.unlock_at).to equal @topic[:delayed_post_at]
    end

    it "always updates unlock_at and sets delayed_post_at to the same value" do
      @topic.delayed_post_at = nil
      expect(@topic[:delayed_post_at]).to be_nil
      expect(@topic[:unlock_at]).to eq @topic.delayed_post_at
      expect(@topic.delayed_post_at).to eq @topic.unlock_at

      @topic[:delayed_post_at] = 5.days.from_now
      @topic[:unlock_at] = nil
      @topic.unlock_at = 1.day.from_now
      expect(@topic[:delayed_post_at]).to eq @topic[:unlock_at]
      expect(@topic[:unlock_at]).to eq @topic.delayed_post_at
      expect(@topic.delayed_post_at).to eq @topic.unlock_at
    end
  end

  describe "visible_ids_by_user" do
    def add_section_to_topic(topic, section)
      topic.is_section_specific = true
      topic.discussion_topic_section_visibilities <<
        DiscussionTopicSectionVisibility.new(
          discussion_topic: topic,
          course_section: section,
          workflow_state: "active"
        )
      topic.save!
    end

    def add_section_differentiation_to_topic(topic, section)
      topic.update!(only_visible_to_overrides: true)
      topic.assignment_overrides.create!(set: section)
      topic.save!
    end

    def add_student_differentiation_to_topic(topic, student)
      topic.update!(only_visible_to_overrides: true)
      override = topic.assignment_overrides.create!
      override.assignment_override_students.create!(user: student)
      topic.save!
    end

    def discussion_and_assignment(opts = {})
      assignment = @course.assignments.create!({
        title: "some discussion assignment",
        submission_types: "discussion_topic"
      }.merge(opts))
      [assignment.discussion_topic, assignment]
    end

    describe "differentiated topics" do
      before :once do
        @course = course_factory(active_course: true)

        @item_without_assignment = discussion_topic_model(user: @teacher)
        @item_with_assignment_and_only_vis, @assignment = discussion_and_assignment(only_visible_to_overrides: true)
        @item_with_assignment_and_visible_to_all, @assignment2 = discussion_and_assignment(only_visible_to_overrides: false)
        @item_with_override_for_section_with_no_students, @assignment3 = discussion_and_assignment(only_visible_to_overrides: true)
        @item_with_no_override, @assignment4 = discussion_and_assignment(only_visible_to_overrides: true)

        @course_section = @course.course_sections.create
        @student1, @student2, @student3 = create_users(3, return_type: :record)
        @course.enroll_student(@student2, enrollment_state: "active")
        @section = @course.course_sections.create!(name: "test section")
        @section2 = @course.course_sections.create!(name: "second test section")
        student_in_section(@section, user: @student1)
        create_section_override_for_assignment(@assignment, { course_section: @section })
        create_section_override_for_assignment(@assignment3, { course_section: @section2 })
        @course.reload
        @vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [@course.id], user_id: [@student1, @student2, @student3].map(&:id))
      end

      it "returns both topics for a student with an override" do
        expect(@vis_hash[@student1.id].sort).to eq [
          @item_without_assignment.id,
          @item_with_assignment_and_only_vis.id,
          @item_with_assignment_and_visible_to_all.id
        ].sort
      end

      it "does not return differentiated topics to a student with no overrides" do
        expect(@vis_hash[@student2.id].sort).to eq [
          @item_without_assignment.id,
          @item_with_assignment_and_visible_to_all.id
        ].sort
      end
    end

    describe "section specific topic" do
      it "filters section specific topics properly" do
        course = course_factory(active_course: true)
        section1 = course.course_sections.create!(name: "test section")
        section2 = course.course_sections.create!(name: "second test section")
        section_specific_topic1 = course.discussion_topics.create!(title: "section specific topic 1")
        section_specific_topic2 = course.discussion_topics.create!(title: "section specific topic 2")
        add_section_to_topic(section_specific_topic1, section1)
        add_section_to_topic(section_specific_topic2, section2)
        student = create_users(1, return_type: :record).first
        course.enroll_student(student, section: section1)
        course.reload
        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student.id], item_type: :discussion)
        expect(vis_hash[student.id].length).to eq(1)
        expect(vis_hash[student.id].first).to eq(section_specific_topic1.id)
      end

      it "properly filters section specific topics for deleted section visibilities" do
        course = course_factory(active_course: true)
        section1 = course.course_sections.create!(name: "section for student")
        section_specific_topic1 = course.discussion_topics.create!(title: "section specific topic 1")
        add_section_to_topic(section_specific_topic1, section1)
        student = create_users(1, return_type: :record).first
        course.enroll_student(student, section: section1)
        course.reload
        section_specific_topic1.destroy
        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student.id], item_type: :discussion)
        expect(vis_hash[student.id].length).to eq(0)
      end

      it "handles sections that don't have any discussion topics" do
        course = course_factory(active_all: true)
        section1 = course.course_sections.create!(name: "section 1")
        section2 = course.course_sections.create!(name: "section 2")
        topic1 = course.discussion_topics.create!(title: "topic 1 (for section 1)")
        add_section_to_topic(topic1, section1)
        student = user_factory(active_all: true)
        course.enroll_student(student, section: section2)
        course.reload

        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student.id], item_type: :discussion)
        expect(vis_hash[student.id].length).to be(0)
      end

      it "handles user not enrolled in any sections" do
        course = course_factory(active_all: true)
        section1 = course.course_sections.create!(name: "section 1")
        topic1 = course.discussion_topics.create!(title: "topic 1 (for section 1)")
        add_section_to_topic(topic1, section1)
        student = user_factory(active_all: true)
        course.reload

        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student.id], item_type: :discussion)
        expect(vis_hash[student.id].length).to be(0)
      end
    end

    describe "differentiated modules" do
      it "filters based on adhoc overrides" do
        course = course_factory(active_course: true)
        student_specific_topic = course.discussion_topics.create!(title: "student specific topic 1")
        student_specific_topic2 = course.discussion_topics.create!(title: "student specific topic 2")

        student1 = create_users(1, return_type: :record).first
        course.enroll_student(student1)
        student2 = create_users(1, return_type: :record).first
        course.enroll_student(student2)
        course.reload

        add_student_differentiation_to_topic(student_specific_topic, student1)
        add_student_differentiation_to_topic(student_specific_topic2, student2)

        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student1.id], item_type: :discussion)
        expect(vis_hash[student1.id].length).to eq(1)
        expect(vis_hash[student1.id].first).to eq(student_specific_topic.id)
      end

      it "filters based on section overrides" do
        course = course_factory(active_course: true)
        section1 = course.course_sections.create!(name: "test section")
        section2 = course.course_sections.create!(name: "second test section")
        section_specific_topic1 = course.discussion_topics.create!(title: "section specific topic 1")
        section_specific_topic2 = course.discussion_topics.create!(title: "section specific topic 2")
        add_section_differentiation_to_topic(section_specific_topic1, section1)
        add_section_differentiation_to_topic(section_specific_topic2, section2)
        student = create_users(1, return_type: :record).first
        course.enroll_student(student, section: section1)
        course.reload
        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student.id], item_type: :discussion)
        expect(vis_hash[student.id].length).to eq(1)
        expect(vis_hash[student.id].first).to eq(section_specific_topic1.id)
      end

      it "filters legacy section specific topics properly" do
        course = course_factory(active_course: true)
        section1 = course.course_sections.create!(name: "test section")
        section2 = course.course_sections.create!(name: "second test section")
        section_specific_topic1 = course.discussion_topics.create!(title: "section specific topic 1")
        section_specific_topic2 = course.discussion_topics.create!(title: "section specific topic 2")
        add_section_to_topic(section_specific_topic1, section1)
        add_section_to_topic(section_specific_topic2, section2)
        student = create_users(1, return_type: :record).first
        course.enroll_student(student, section: section1)
        course.reload
        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [course.id], user_id: [student.id], item_type: :discussion)
        expect(vis_hash[student.id].length).to eq(1)
        expect(vis_hash[student.id].first).to eq(section_specific_topic1.id)
      end

      it "filters graded discussions correctly" do
        @course = course_factory(active_course: true)
        section1 = @course.course_sections.create!(name: "Section 1")
        section2 = @course.course_sections.create!(name: "Section 2")
        student1 = user_factory(active_all: true)
        student2 = user_factory(active_all: true)
        @course.enroll_student(student1, section: section1)
        @course.enroll_student(student2, section: section2)

        # Create graded discussions with differentiation
        discussion1 = discussion_and_assignment(only_visible_to_overrides: true).first
        discussion2 = discussion_and_assignment(only_visible_to_overrides: true).first

        create_section_override_for_assignment(discussion1.assignment, { course_section: section1 })
        create_section_override_for_assignment(discussion2.assignment, { course_section: section2 })

        vis_hash = DiscussionTopic.visible_ids_by_user(course_id: [@course.id], user_id: [student1.id, student2.id])
        expect(vis_hash[student1.id]).to contain_exactly(discussion1.id)
        expect(vis_hash[student2.id]).to contain_exactly(discussion2.id)
      end
    end
  end

  describe "user_can_summarize" do
    before do
      @course = course_factory(active_all: true)
      @admin = account_admin_user(account: @course.root_account)
      @teacher = user_model
      @course.enroll_teacher(@teacher, enrollment_state: "active")
      @student = user_model
      @course.enroll_student(@student, enrollment_state: "active")
      @observer = user_model
      @course.enroll_user(@observer, "ObserverEnrollment").update_attribute(:associated_user_id, @student.id)
      @ta = user_model
      @course.enroll_ta(@ta, enrollment_state: "active")
      @designer = user_model
      @course.enroll_designer(@designer, enrollment_state: "active")

      @topic = @course.discussion_topics.create!(title: "topic")
    end

    it "does not allow to summarize if the feature is disabled" do
      expect(@topic.user_can_summarize?(@teacher)).to be false
      expect(@topic.user_can_summarize?(@ta)).to be false
      expect(@topic.user_can_summarize?(@admin)).to be false
      expect(@topic.user_can_summarize?(@designer)).to be false
      expect(@topic.user_can_summarize?(@observer)).to be false
      expect(@topic.user_can_summarize?(@student)).to be false
    end

    it "allows instructors and read admins to summarize if the feature is enabled" do
      @course.enable_feature!(:discussion_summary)

      expect(@topic.user_can_summarize?(@teacher)).to be true
      expect(@topic.user_can_summarize?(@ta)).to be true
      expect(@topic.user_can_summarize?(@admin)).to be true
      expect(@topic.user_can_summarize?(@designer)).to be true

      expect(@topic.user_can_summarize?(@observer)).to be false
      expect(@topic.user_can_summarize?(@student)).to be false
    end

    it "does not crash if the topic is in the context of a group with account context" do
      account = @course.root_account
      account.enable_feature!(:discussion_summary)
      group = account.groups.create!
      topic = group.discussion_topics.create!(title: "topic")

      expect(topic.user_can_summarize?(@teacher)).to be false
      expect(topic.user_can_summarize?(@ta)).to be false
      expect(topic.user_can_summarize?(@admin)).to be false
      expect(topic.user_can_summarize?(@designer)).to be false
      expect(topic.user_can_summarize?(@observer)).to be false
      expect(topic.user_can_summarize?(@student)).to be false
    end
  end

  describe "user_can_access_insights" do
    before do
      @course = course_factory(active_all: true)
      @admin = account_admin_user(account: @course.root_account)
      @teacher = user_model
      @course.enroll_teacher(@teacher, enrollment_state: "active")
      @student = user_model
      @course.enroll_student(@student, enrollment_state: "active")
      @observer = user_model
      @course.enroll_user(@observer, "ObserverEnrollment").update_attribute(:associated_user_id, @student.id)
      @ta = user_model
      @course.enroll_ta(@ta, enrollment_state: "active")
      @designer = user_model
      @course.enroll_designer(@designer, enrollment_state: "active")

      @topic = @course.discussion_topics.create!(title: "topic")
    end

    it "does not allow to access insights if the feature is disabled" do
      expect(@topic.user_can_access_insights?(@teacher)).to be false
      expect(@topic.user_can_access_insights?(@ta)).to be false
      expect(@topic.user_can_access_insights?(@admin)).to be false
      expect(@topic.user_can_access_insights?(@designer)).to be false
      expect(@topic.user_can_access_insights?(@observer)).to be false
      expect(@topic.user_can_access_insights?(@student)).to be false
    end

    it "allows instructors and read admins to access insights if the feature is enabled" do
      @course.enable_feature!(:discussion_insights)

      expect(@topic.user_can_access_insights?(@teacher)).to be true
      expect(@topic.user_can_access_insights?(@ta)).to be true
      expect(@topic.user_can_access_insights?(@admin)).to be true
      expect(@topic.user_can_access_insights?(@designer)).to be true

      expect(@topic.user_can_access_insights?(@observer)).to be false
      expect(@topic.user_can_access_insights?(@student)).to be false
    end

    it "does not crash if the topic is in the context of a group with account context" do
      account = @course.root_account
      account.enable_feature!(:discussion_insights)
      group = account.groups.create!
      topic = group.discussion_topics.create!(title: "topic")

      expect(topic.user_can_access_insights?(@teacher)).to be false
      expect(topic.user_can_access_insights?(@ta)).to be false
      expect(topic.user_can_access_insights?(@admin)).to be false
      expect(topic.user_can_access_insights?(@designer)).to be false
      expect(topic.user_can_access_insights?(@observer)).to be false
      expect(topic.user_can_access_insights?(@student)).to be false
    end
  end

  describe "low_level_locked_for?" do
    before :once do
      @topic = @course.discussion_topics.create!(title: "topic")
    end

    it "is unlocked by default" do
      expect(@topic.low_level_locked_for?(@student)).to be_falsey
    end

    it "is unlocked for past unlock_at date" do
      @topic.update(unlock_at: 1.week.ago)
      expect(@topic.locked_for?(@student)).to be_falsey
    end

    it "is unlocked for future lock_at date" do
      @topic.update(lock_at: 1.week.from_now)
      expect(@topic.locked_for?(@student)).to be_falsey
    end

    it "is locked for future unlock_at date" do
      timestamp = 1.week.from_now
      @topic.update(unlock_at: timestamp)
      lock_info = @topic.locked_for?(@student)
      expect(lock_info).to be_truthy
      expect(lock_info[:unlock_at]).to eq timestamp
    end

    it "is locked for future delayed_post_at date" do
      timestamp = 1.week.from_now
      @topic.update(delayed_post_at: timestamp)
      lock_info = @topic.locked_for?(@student)
      expect(lock_info).to be_truthy
      expect(lock_info[:unlock_at]).to eq timestamp
    end

    it "is locked for past lock_at date" do
      timestamp = 1.week.ago
      @topic.update(lock_at: timestamp)
      lock_info = @topic.locked_for?(@student)
      expect(lock_info).to be_truthy
      expect(lock_info[:lock_at]).to eq timestamp
    end

    it "locks for unpublished module" do
      cm = @course.context_modules.create!(name: "module", workflow_state: "unpublished")
      cm.add_item(type: "discussion_topic", id: @topic.id)
      @topic.update!(could_be_locked: true)
      lock_info = @topic.locked_for?(@student)
      expect(lock_info).to be_truthy
    end

    it "locks for student with override" do
      timestamp = 1.week.from_now
      ao = @topic.assignment_overrides.create!(unlock_at: timestamp, unlock_at_overridden: true)
      ao.assignment_override_students.create!(user: @student)
      lock_info = @topic.locked_for?(@student)
      expect(lock_info).to be_truthy
      expect(lock_info[:unlock_at]).to eq timestamp
    end

    it "unlocks for student with override" do
      @topic.update(lock_at: 1.week.ago)
      ao = @topic.assignment_overrides.create!(lock_at: 1.week.from_now, lock_at_overridden: true)
      ao.assignment_override_students.create!(user: @student)
      lock_info = @topic.locked_for?(@student)
      expect(lock_info).to be_falsey
    end

    it "does not fall back to base delayed_post_at for student with override" do
      @topic.update!(delayed_post_at: 1.week.from_now)
      ao = @topic.assignment_overrides.create!(unlock_at: 1.week.ago, unlock_at_overridden: true)
      ao.assignment_override_students.create!(user: @student)
      expect(@topic.locked_for?(@student)).to be_falsey
    end

    it "is unlocked for teacher regardless of dates" do
      @topic.update(lock_at: 1.week.ago)
      expect(@topic.locked_for?(@teacher, check_policies: true)).to be_falsey
      expect(@topic.locked_for?(@student, check_policies: true)).to be_truthy
    end

    it "is unlocked for students with moderate_forum regardless of dates" do
      @topic.update(lock_at: 1.week.ago)
      expect(@topic.locked_for?(@student, check_policies: true)).to be_truthy
      RoleOverride.create!(context: @course.account, permission: "moderate_forum", role: student_role, enabled: true)
      AdheresToPolicy::Cache.clear
      expect(@topic.locked_for?(@student, check_policies: true)).to be_falsey
    end

    it "is locked if locked column is true" do
      @topic.update(locked: true)
      expect(@topic.locked_for?(@student)).to be_truthy
    end

    context "with an assignment" do
      before :once do
        @assignment = @course.assignments.create!(title: "assignment")
        @topic.update!(assignment: @assignment)
      end

      it "is unlocked by default" do
        expect(@topic.locked_for?(@student)).to be_falsey
      end

      it "prefers the assignment's dates" do
        @topic.update(unlock_at: 1.week.from_now)
        expect(@topic.locked_for?(@student)).to be_falsey
      end

      it "does not enforce the topic's overrides" do
        ao = @topic.assignment_overrides.create!(unlock_at: 1.week.from_now, unlock_at_overridden: true)
        ao.assignment_override_students.create!(user: @student)
        expect(@topic.locked_for?(@student)).to be_falsey
      end

      it "respects assignment's unlock_at" do
        timestamp = 1.week.from_now
        @assignment.update!(unlock_at: timestamp)
        lock_info = @topic.locked_for?(@student)
        expect(lock_info).to be_truthy
        expect(lock_info[:unlock_at]).to eq timestamp
      end

      it "respects assignment's lock_at" do
        timestamp = 1.week.ago
        @assignment.update!(lock_at: timestamp)
        lock_info = @topic.locked_for?(@student)
        expect(lock_info).to be_truthy
        expect(lock_info[:lock_at]).to eq timestamp
      end

      it "respects assignment's overrides" do
        timestamp = 1.week.from_now
        ao = @assignment.assignment_overrides.create!(unlock_at: timestamp, unlock_at_overridden: true)
        ao.assignment_override_students.create!(user: @student)
        lock_info = @topic.locked_for?(@student)
        expect(lock_info).to be_truthy
        expect(lock_info[:unlock_at]).to eq timestamp
      end

      it "respects assignment's overrides when discussion is locked for everyone else" do
        timestamp = 1.week.from_now
        @topic.update!(lock_at: 1.week.ago)
        ao = @assignment.assignment_overrides.create!(lock_at: timestamp, lock_at_overridden: true)
        ao.assignment_override_students.create!(user: @student)
        lock_info = @topic.locked_for?(@student)
        expect(lock_info).to be_falsey
      end
    end
  end

  describe "edited_at" do
    it "returns null if no change to the title or message occurred" do
      topic = discussion_topic_model
      expect(topic.edited_at).to be_nil
      topic.context_code = "other context"
      topic.save!
      expect(topic.edited_at).to be_nil
    end

    it "returns not null if a change to the title occured" do
      topic = discussion_topic_model
      expect(topic.edited_at).to be_nil
      topic.title = "Brand new shinny title"
      topic.save!
      expect(topic.edited_at).not_to be_nil
    end

    it "returns not null if a change to the message occured" do
      topic = discussion_topic_model
      expect(topic.edited_at).to be_nil
      topic.message = "Brand new shinny message"
      topic.save!
      expect(topic.edited_at).not_to be_nil
    end
  end

  describe "show_in_search_for_user?" do
    shared_examples_for "expected_values_for_teacher_student" do |teacher_expected, student_expected|
      it "is #{teacher_expected} for teacher" do
        expect(topic.show_in_search_for_user?(@teacher)).to eq(teacher_expected)
      end

      it "is #{student_expected} for student" do
        expect(topic.show_in_search_for_user?(@student)).to eq(student_expected)
      end
    end

    let(:topic) { @course.discussion_topics.create!(title: "topic") }

    before(:once) do
      course_with_teacher(active_all: true)
      student_in_course(active_all: true)
    end

    include_examples "expected_values_for_teacher_student", true, true

    context "topic is locked" do
      let(:topic) { @course.discussion_topics.create!(title: "locked topic", unlock_at: 1.week.from_now) }

      include_examples "expected_values_for_teacher_student", true, false

      context "and was previously unlocked" do
        before { topic.update!(lock_at: 1.week.ago, unlock_at: 2.weeks.ago) }

        include_examples "expected_values_for_teacher_student", true, true
      end
    end

    context "topic is delayed" do
      let(:topic) { @course.discussion_topics.create!(title: "delayed topic", delayed_post_at: 1.week.from_now) }

      include_examples "expected_values_for_teacher_student", true, false
    end

    context "topic is unpublished" do
      let(:topic) { @course.discussion_topics.create!(title: "unpublished topic", workflow_state: "unpublished") }

      include_examples "expected_values_for_teacher_student", true, false
    end

    context "topic is deleted" do
      let(:topic) do
        topic = @course.discussion_topics.create!(title: "deleted topic", workflow_state: "deleted")
        topic.destroy!
        topic
      end

      include_examples "expected_values_for_teacher_student", false, false
    end

    context "topic is in a module" do
      let(:topic) { @course.discussion_topics.create!(title: "module topic") }

      before do
        @context_module = @course.context_modules.create!(name: "module")
        @context_module.add_item(type: "discussion_topic", id: topic.id)
        @context_module.save!

        second_module = @course.context_modules.create!(name: "module", workflow_state: "unpublished")
        second_module.add_item(type: "discussion_topic", id: topic.id)
        second_module.save!
      end

      after do
        @course.context_modules.destroy_all
      end

      include_examples "expected_values_for_teacher_student", true, true

      context "and the module is unpublished" do
        before do
          @context_module.unpublish!
        end

        include_examples "expected_values_for_teacher_student", true, false
      end

      context "and the module is locked" do
        before do
          @context_module.update!(unlock_at: 1.week.from_now)
        end

        include_examples "expected_values_for_teacher_student", true, false
      end
    end
  end

  describe "#can_unpublish?" do
    context "discussion topic with checkpoints" do
      before do
        @course.account.enable_feature!(:discussion_checkpoints)
        @reply_to_topic, _, @topic = graded_discussion_topic_with_checkpoints(context: @course, reply_to_entry_required_count: 2)
      end

      it "returns true if there are no student submissions" do
        expect(@topic.can_unpublish?).to be true
      end

      it "returns false if there are student sub_assignment submissions" do
        @reply_to_topic.submit_homework @student, body: "reply to entry submission for #{@student.name}"
        expect(@topic.can_unpublish?).to be false
      end
    end
  end

  describe "sort_order and expand" do
    before(:once) do
      @topic = @course.discussion_topics.create!(sort_order: "asc")
    end

    it "replaces incorrect value with default" do
      @topic.sort_order = "incorrect sort order"
      @topic.save!
      expect(@topic.reload.sort_order).to eq DiscussionTopic::SortOrder::DEFAULT
    end

    it "returns the sort order of the topic" do
      @topic.update!(sort_order: "asc", sort_order_locked: true)
      @topic.update_or_create_participant(current_user: @student, sort_order: "desc")
      expect(@topic.sort_order_for_user).to eq "asc"
    end

    context "when the sort order is not locked" do
      before do
        @topic.update!(sort_order_locked: false)
      end

      it "returns the participant's sort order if it exists" do
        @topic.update_or_create_participant(current_user: @student, sort_order: "desc")
        expect(@topic.sort_order_for_user(@student)).to eq "desc"
      end

      it "falls back to the topic's sort order if the participant's sort order is not set" do
        @topic.update_or_create_participant(current_user: @student, sort_order: "inherit")
        expect(@topic.sort_order_for_user(@student)).to eq DiscussionTopic::SortOrder::ASC
        @topic.sort_order = DiscussionTopic::SortOrder::DESC
        @topic.save!
        expect(@topic.sort_order_for_user(@student)).to eq DiscussionTopic::SortOrder::DESC
      end
    end

    context "topic participant when creating the topic" do
      it "does create the participant with the proper expanded and sort order values" do
        sort_order = "asc"
        expanded = false
        topic1 = @course.discussion_topics.create!(user: @teacher, sort_order:, expanded:)

        expect(topic1.sort_order_for_user(@teacher)).to eq sort_order
        expect(topic1.expanded_for_user(@teacher)).to eq expanded

        sort_order = "desc"
        expanded = true
        topic2 = @course.discussion_topics.create!(user: @teacher, sort_order:, expanded:)

        expect(topic2.sort_order_for_user(@teacher)).to eq sort_order
        expect(topic2.expanded_for_user(@teacher)).to eq expanded
      end
    end

    context "subtopic" do
      it "create subtopic with same values" do
        group_discussion_assignment
        subtopic = @topic.child_topics.first
        expect(subtopic.sort_order).to eq @topic.sort_order
        expect(subtopic.expanded).to eq @topic.expanded
        expect(subtopic.sort_order_locked).to eq @topic.sort_order_locked
      end

      it "update subtopic with same values" do
        group_discussion_assignment
        @topic.update!(sort_order: "desc", expanded: true, expanded_locked: true, sort_order_locked: false)
        subtopic = @topic.child_topics.first
        expect(subtopic.sort_order).to eq "desc"
        expect(subtopic.expanded).to be true
        expect(subtopic.sort_order_locked).to be false
        expect(subtopic.expanded_locked).to be true
      end
    end
  end
end
