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

describe Group do
  before :once do
    course_model
    group_model(context: @course)
  end

  context "validation" do
    it "creates a new instance given valid attributes" do
      group_model
    end
  end

  it "has a wiki" do
    expect(@group.wiki).not_to be_nil
  end

  it "is private by default" do
    expect(@group.is_public).to be_falsey
  end

  it "allows a private group to be made public" do
    @communities = GroupCategory.communities_for(Account.default)
    group_model(group_category: @communities, is_public: false)
    @group.is_public = true
    @group.save!
    expect(@group.reload.is_public).to be_truthy
  end

  it "does not allow a public group to be made private" do
    @communities = GroupCategory.communities_for(Account.default)
    group_model(group_category: @communities, is_public: true)
    @group.is_public = false
    expect(@group.save).to be_falsey
    expect(@group.reload.is_public).to be_truthy
  end

  it "delegates time_zone through to its context" do
    zone = ActiveSupport::TimeZone["America/Denver"]
    @course.time_zone = zone
    expect(@group.time_zone.to_s).to match(/Mountain Time/)
  end

  it "identifies a group as active correctly" do
    course_with_student(active_all: true)
    group_model(group_category: @communities, is_public: true)
    group.add_user(@student)
    expect(@group.inactive?).to be false
  end

  it "identifies a destroyed course as not active" do
    course_with_student(active_all: true)
    group_model(group_category: @communities, is_public: true)
    group.add_user(@student)
    @group.context = @course
    @course.destroy!
    expect(@group.inactive?).to be true
  end

  it "identifies a concluded course as not active" do
    course_with_student(active_all: true)
    group_model(group_category: @communities, is_public: true)
    group.add_user(@student)
    @group.context = @course
    @course.complete!
    expect(@group.inactive?).to be true
  end

  it "identifies an account group as not active correctly" do
    @account = account_model
    group_model(group_category: @communities, is_public: true, context: @account)
    group.add_user(@student)
    @group.context.destroy
    expect(@group.inactive?).to be true
  end

  it "identifies an account group as active" do
    @account = account_model
    group_model(group_category: @communities, is_public: true, context: @account)
    group.add_user(@student)
    expect(@group.inactive?).to be false
  end

  it "sets the root_account_id for GroupMemberships when bulk adding users" do
    @account = account_model
    group_model(group_category: @communities, is_public: true, context: @account)
    @group.bulk_add_users_to_group([@user])
    @group.group_memberships.each do |gm|
      expect(gm.root_account_id).not_to be_nil
    end
  end

  it "does not create new group if Horizon course" do
    context = course_model
    group_category = context.group_categories.create(name: "worldCup")
    @course.account.enable_feature!(:horizon_course_setting)
    @course.update!(horizon_course: true)
    @course.save!
    expect do
      Group.create!(name: "group1", group_category:, context:)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  describe "#grading_standard_or_default" do
    context "when the Group belongs to a Course" do
      it "returns the grading scheme being used by the course, if one exists" do
        standard = grading_standard_for(@course)
        @course.update!(grading_standard: standard)
        expect(@group.grading_standard_or_default).to be standard
      end

      it "returns the Canvas default grading scheme if the course is not using a grading scheme" do
        expect(@group.grading_standard_or_default.data).to eq GradingStandard.default_grading_standard
      end
    end

    context "Group belonging to an Account" do
      it "returns the Canvas default grading scheme" do
        group = group_model(context: Account.default)
        expect(group.grading_standard_or_default.data).to eq GradingStandard.default_grading_standard
      end
    end
  end

  describe "#peer_groups" do
    it "finds all peer groups" do
      context = course_model
      group_category = context.group_categories.create(name: "worldCup")
      other_category = context.group_categories.create(name: "other category")
      group1 = Group.create!(name: "group1", group_category:, context:)
      group2 = Group.create!(name: "group2", group_category:, context:)
      group3 = Group.create!(name: "group3", group_category:, context:)
      group4 = Group.create!(name: "group4", group_category: other_category, context:)
      expect(group1.peer_groups.length).to eq 2
      expect(group1.peer_groups).to include(group2)
      expect(group1.peer_groups).to include(group3)
      expect(group1.peer_groups).not_to include(group1)
      expect(group1.peer_groups).not_to include(group4)
    end

    it "does not find peer groups for student organized groups" do
      context = course_model
      group_category = GroupCategory.student_organized_for(context)
      group1 = Group.create!(name: "group1", group_category:, context:)
      Group.create!(name: "group2", group_category:, context:)
      expect(group1.peer_groups).to be_empty
    end
  end

  context "atom" do
    it "has an atom name as it's own name" do
      group_model(name: "some unique name")
      expect(@group.to_atom[:title]).to eql("some unique name")
    end

    it "has a link to itself" do
      link = @group.to_atom[:link]
      expect(link).to eql("/groups/#{@group.id}")
    end
  end

  context "add_user" do
    it "is able to add a person to the group" do
      user_model
      pseudonym_model(user_id: @user.id)
      @group.add_user(@user)
      expect(@group.users).to include(@user)
    end

    it "is not able to add a person to the group twice" do
      user_model
      pseudonym_model(user_id: @user.id)
      @group.add_user(@user)
      expect(@group.users).to include(@user)
      expect(@group.users.count).to eq 1
      @group.add_user(@user)
      @group.reload
      expect(@group.users).to include(@user)
      expect(@group.users.count).to eq 1
    end

    it "removes that user from peer groups" do
      context = course_model
      group_category = context.group_categories.create!(name: "worldCup")
      group1 = Group.create!(name: "group1", group_category:, context:)
      group2 = Group.create!(name: "group2", group_category:, context:)
      user_model
      pseudonym_model(user_id: @user.id)
      group1.add_user(@user)
      expect(group1.users).to include(@user)

      group2.add_user(@user)
      expect(group2.users).to include(@user)
      group1.reload
      expect(group1.users).not_to include(@user)
    end

    it "adds a user at the right workflow_state by default" do
      @communities = GroupCategory.communities_for(Account.default)
      user_model
      {
        "invitation_only" => "invited",
        "parent_context_request" => "requested",
        "parent_context_auto_join" => "accepted"
      }.each do |join_level, workflow_state|
        group = group_model(join_level:, group_category: @communities)
        group.add_user(@user)
        expect(group.group_memberships.where(workflow_state:, user_id: @user).first).not_to be_nil
      end
    end

    it "allows specifying a workflow_state" do
      @communities = GroupCategory.communities_for(Account.default)
      @group.group_category = @communities
      @group.save!
      user_model

      %w[invited requested accepted].each do |workflow_state|
        @group.add_user(@user, workflow_state)
        expect(@group.group_memberships.where(workflow_state:, user_id: @user).first).not_to be_nil
      end
    end

    it "allows specifying that the user should be a moderator" do
      user_model
      @membership = @group.add_user(@user, "accepted", true)
      expect(@membership.moderator).to be true
    end

    it "changes the workflow_state of an already active user" do
      @communities = GroupCategory.communities_for(Account.default)
      @group.group_category = @communities
      @group.save!
      user_model
      @group.add_user(@user, "accepted")
      @membership = @group.add_user(@user, "requested")
      expect(@membership.workflow_state).to eq "accepted"
    end
  end

  it "grants manage permissions for associated objects to group managers" do
    e = course_with_teacher(active_course: true)
    course = e.context
    teacher = e.user
    group = course.groups.create
    expect(course.grants_right?(teacher, :manage_groups_add)).to be_truthy
    expect(course.grants_right?(teacher, :manage_groups_manage)).to be_truthy
    expect(course.grants_right?(teacher, :manage_groups_delete)).to be_truthy
    expect(group.grants_right?(teacher, :manage_wiki_create)).to be_truthy
    expect(group.grants_right?(teacher, :manage_wiki_update)).to be_truthy
    expect(group.grants_right?(teacher, :manage_wiki_delete)).to be_truthy
    expect(group.grants_right?(teacher, :manage_files_add)).to be_truthy
    expect(group.grants_right?(teacher, :manage_files_edit)).to be_truthy
    expect(group.grants_right?(teacher, :manage_files_delete)).to be_truthy
    expect(group.wiki.grants_right?(teacher, :update_page)).to be_truthy
    attachment = group.attachments.build
    expect(attachment.grants_right?(teacher, :create)).to be_truthy
  end

  it "does not allow a concluded student to participate" do
    course_with_student(active_all: true)
    group = @course.groups.create
    group.add_user(@student)

    @student.enrollments.first.conclude
    expect(group.grants_right?(@student, :participate)).to be_falsey
  end

  it "only allows me to moderate_forum if I can moderate_forum of group's context" do
    course_with_teacher(active_course: true)
    student_in_course
    group = @course.groups.create

    expect(group.grants_right?(@teacher, :moderate_forum)).to be_truthy
    expect(group.grants_right?(@student, :moderate_forum)).to be_falsey
  end

  it "grants messaging rights to students if messaging permissions are enabled" do
    course_with_teacher(active_course: true)
    student_in_course(course: @course)
    group = @course.groups.create
    group.add_user(@student)

    expect(group.grants_right?(@teacher, :send_messages)).to be_truthy
    expect(group.grants_right?(@student, :send_messages)).to be_truthy # by default
    expect(group.grants_right?(@student, :send_messages_all)).to be_truthy
  end

  it "does not grant messaging rights to students if messaging permissions are disabled" do
    course_with_teacher(active_course: true)
    student_in_course(course: @course)
    group = @course.groups.create
    group.add_user(@student)
    @course.account.role_overrides.create!(permission: :send_messages, role: student_role, enabled: false)

    expect(group.grants_right?(@teacher, :send_messages)).to be_truthy
    expect(group.grants_right?(@student, :send_messages)).to be_falsey
    expect(group.grants_right?(@student, :send_messages_all)).to be_falsey
  end

  it "grants read_roster permissions to students that can freely join or request an invitation to the group" do
    course_with_teacher(active_course: true)
    student_in_course.accept!

    # default join_level == 'invitation_only' and default category is not self-signup
    group = @course.groups.create
    expect(group.grants_right?(@student, :read_roster)).to be_falsey

    # join_level allows requesting group membership
    group = @course.groups.create(join_level: "parent_context_request")
    expect(group.grants_right?(@student, :read_roster)).to be_truthy

    # category is self-signup
    category = @course.group_categories.build(name: "category name")
    category.self_signup = "enabled"
    category.save
    group = @course.groups.create(group_category: category)
    expect(group.grants_right?(@student, :read_roster)).to be_truthy
  end

  describe "root account" do
    it "gets the root account assigned" do
      course_with_teacher
      group = @course.groups.create!
      expect(group.account).to eq Account.default
      expect(group.root_account).to eq Account.default

      new_root_acct = account_model
      new_sub_acct = new_root_acct.sub_accounts.create!(name: "sub acct")
      group.context = new_sub_acct
      group.save!
      expect(group.account).to eq new_sub_acct
      expect(group.root_account).to eq new_root_acct
    end
  end

  context "auto_accept?" do
    it "is false unless join level is 'parent_context_auto_join'" do
      course_with_student

      group_category = GroupCategory.student_organized_for(@course)
      group1 = @course.groups.create(group_category:, join_level: "parent_context_auto_join")
      group2 = @course.groups.create(group_category:, join_level: "parent_context_request")
      group3 = @course.groups.create(group_category:, join_level: "invitation_only")
      expect([group1, group2, group3].map(&:auto_accept?)).to eq [true, false, false]
    end

    it "is false unless the group is student organized or a community" do
      course_with_student
      @account = @course.root_account

      jl = "parent_context_auto_join"
      group1 = @course.groups.create(group_category: @course.group_categories.create(name: "random category"), join_level: jl)
      group2 = @course.groups.create(group_category: GroupCategory.student_organized_for(@course), join_level: jl)
      group3 = @account.groups.create(group_category: GroupCategory.communities_for(@account), join_level: jl)
      expect([group1, group2, group3].map(&:auto_accept?)).to eq [false, true, true]
    end
  end

  context "allow_join_request?" do
    it "is false unless join level is 'parent_context_auto_join' or 'parent_context_request'" do
      course_with_student

      group_category = GroupCategory.student_organized_for(@course)
      group1 = @course.groups.create(group_category:, join_level: "parent_context_auto_join")
      group2 = @course.groups.create(group_category:, join_level: "parent_context_request")
      group3 = @course.groups.create(group_category:, join_level: "invitation_only")
      expect([group1, group2, group3].map(&:allow_join_request?)).to eq [true, true, false]
    end

    it "is false unless the group is student organized or a community" do
      course_with_student
      @account = @course.root_account

      jl = "parent_context_auto_join"
      group1 = @course.groups.create(group_category: @course.group_categories.create(name: "random category"), join_level: jl)
      group2 = @course.groups.create(group_category: GroupCategory.student_organized_for(@course), join_level: jl)
      group3 = @account.groups.create(group_category: GroupCategory.communities_for(@account), join_level: jl)
      expect([group1, group2, group3].map(&:allow_join_request?)).to eq [false, true, true]
    end
  end

  context "allow_self_signup?" do
    it "follows the group category self signup option" do
      course_with_student

      group_category = GroupCategory.student_organized_for(@course)
      group_category.configure_self_signup(true, false)
      group_category.save!
      group1 = @course.groups.create(group_category:)
      expect(group1.allow_self_signup?(@student)).to be_truthy

      group_category.configure_self_signup(true, true)
      group_category.save!
      group2 = @course.groups.create(group_category:)
      expect(group2.allow_self_signup?(@student)).to be_truthy

      group_category.configure_self_signup(false, false)
      group_category.save!
      group3 = @course.groups.create(group_category:)
      expect(group3.allow_self_signup?(@student)).to be_falsey
    end

    it "handles restricted course sections correctly" do
      course_with_student
      @other_section = @course.course_sections.create!(name: "Other Section")
      @other_student = @course.enroll_student(user_model, { section: @other_section }).user

      group_category = GroupCategory.student_organized_for(@course)
      group_category.configure_self_signup(true, true)
      group_category.save!
      group1 = @course.groups.create(group_category:)
      expect(group1.allow_self_signup?(@student)).to be_truthy
      group1.add_user(@student)
      group1.reload
      expect(group1.allow_self_signup?(@other_student)).to be_falsey
    end
  end

  describe "#full?" do
    it "returns true when category group_limit has been met" do
      @group.group_category = @course.group_categories.build(name: "foo", group_limit: 1)
      @group.add_user user_model, "accepted"
      @group.association(:participating_users).reset
      expect(@group).to be_full
    end

    it "returns true when max_membership has been met" do
      @group.group_category = @course.group_categories.build(name: "foo", group_limit: 0)
      @group.max_membership = 1
      @group.add_user user_model, "accepted"
      @group.association(:participating_users).reset
      expect(@group).to be_full
    end

    it "returns false when max_membership has not been met" do
      @group.group_category = @course.group_categories.build(name: "foo", group_limit: 0)
      @group.max_membership = 2
      @group.add_user user_model, "accepted"
      @group.association(:participating_users).reset
      expect(@group).not_to be_full
    end

    it "returns false when category group_limit has not been met" do
      # no category
      expect(@group).not_to be_full
      # not full
      @group.group_category = @course.group_categories.build(name: "foo", group_limit: 2)
      @group.add_user user_model, "accepted"
      @group.association(:participating_users).reset
      expect(@group).not_to be_full
    end
  end

  context "has_member?" do
    it "is true for accepted memberships, regardless of moderator flag" do
      @user1 = user_model
      @user2 = user_model
      @user3 = user_model
      @user4 = user_model
      @user5 = user_model

      @group.add_user(@user1, "accepted")
      @group.add_user(@user2, "accepted")
      @group.add_user(@user3, "invited")
      @group.add_user(@user4, "requested")
      @group.add_user(@user5, "rejected")
      GroupMembership.where(group_id: @group, user_id: @user2).update_all(moderator: true)

      expect(@group.has_member?(@user1)).to be_truthy
      expect(@group.has_member?(@user2)).to be_truthy
      expect(@group.has_member?(@user3)).to be_truthy # false when we turn auto_join off
      expect(@group.has_member?(@user4)).to be_truthy # false when we turn auto_join off
      expect(@group.has_member?(@user5)).to be_falsey
    end
  end

  context "has_moderator?" do
    it "is true for accepted memberships, with moderator flag" do
      @user1 = user_model
      @user2 = user_model
      @user3 = user_model
      @user4 = user_model
      @user5 = user_model

      @group.add_user(@user1, "accepted")
      @group.add_user(@user2, "accepted")
      @group.add_user(@user3, "invited")
      @group.add_user(@user4, "requested")
      @group.add_user(@user5, "rejected")
      GroupMembership.where(group_id: @group, user_id: [@user2, @user3, @user4, @user5]).update_all(moderator: true)

      expect(@group.has_moderator?(@user1)).to be_falsey
      expect(@group.has_moderator?(@user2)).to be_truthy
      expect(@group.has_moderator?(@user3)).to be_truthy # false when we turn auto_join off
      expect(@group.has_moderator?(@user4)).to be_truthy # false when we turn auto_join off
      expect(@group.has_moderator?(@user5)).to be_falsey
    end
  end

  context "user_can_manage_own_discussion_posts" do
    it "returns true if the context is an account" do
      account = Account.default
      group = account.groups.create
      expect(group.user_can_manage_own_discussion_posts?(nil)).to be_truthy
    end

    it "defers to the context if that context is a course" do
      course_with_student
      group = @course.groups.create
      allow(group.context).to receive(:user_can_manage_own_discussion_posts?).and_return(false)
      expect(group.user_can_manage_own_discussion_posts?(nil)).to be_falsey
    end
  end

  context "invite_user" do
    it "autoes accept invitations" do
      course_with_student(active_all: true)

      group_category = GroupCategory.student_organized_for(@course)

      group = @course.groups.create!(group_category:)
      gm = group.invite_user(@student)
      expect(gm).to be_accepted
    end
  end

  context "request_user" do
    it "autoes accept invitations" do
      course_with_student(active_all: true)

      group_category = GroupCategory.student_organized_for(@course)

      group = @course.groups.create!(group_category:, join_level: "parent_context_auto_join")
      gm = group.request_user(@student)
      expect(gm).to be_accepted
    end
  end

  it "defaults group_category to student organized category on save" do
    course_with_teacher
    group = @course.groups.create
    expect(group.group_category).to eq GroupCategory.student_organized_for(@course)

    group_category = @course.group_categories.create(name: "random category")
    group = @course.groups.create(group_category:)
    expect(group.group_category).to eq group_category
  end

  it "as_json should include group_category" do
    course_factory
    gc = group_category(name: "Something")
    group = Group.create(group_category: gc)
    hash = group.as_json
    expect(hash["group"]["group_category"]).to eq "Something"
  end

  context "has_common_section?" do
    it "is false for accounts" do
      account = Account.default
      group = account.groups.create
      expect(group).not_to have_common_section
    end

    it "is not true if two members don't share a section" do
      course_with_teacher(active_all: true)
      section1 = @course.course_sections.create
      section2 = @course.course_sections.create
      user1 = section1.enroll_user(user_model, "StudentEnrollment").user
      user2 = section2.enroll_user(user_model, "StudentEnrollment").user
      group = @course.groups.create
      group.add_user(user1)
      group.add_user(user2)
      expect(group).not_to have_common_section
    end

    it "is true if all members group have a section in common" do
      course_with_teacher(active_all: true)
      section1 = @course.course_sections.create
      user1 = section1.enroll_user(user_model, "StudentEnrollment").user
      user2 = section1.enroll_user(user_model, "StudentEnrollment").user
      group = @course.groups.create
      group.add_user(user1)
      group.add_user(user2)
      expect(group).to have_common_section
    end
  end

  context "has_common_section_with_user?" do
    it "is false for accounts" do
      account = Account.default
      group = account.groups.create
      expect(group).not_to have_common_section_with_user(user_model)
    end

    it "is not true if the new member does't share a section with an existing member" do
      course_with_teacher(active_all: true)
      section1 = @course.course_sections.create
      section2 = @course.course_sections.create
      user1 = section1.enroll_user(user_model, "StudentEnrollment").user
      user2 = section2.enroll_user(user_model, "StudentEnrollment").user
      group = @course.groups.create
      group.add_user(user1)
      expect(group).not_to have_common_section_with_user(user2)
    end

    it "is true if all members group have a section in common with the new user" do
      course_with_teacher(active_all: true)
      section1 = @course.course_sections.create
      user1 = section1.enroll_user(user_model, "StudentEnrollment").user
      user2 = section1.enroll_user(user_model, "StudentEnrollment").user
      group = @course.groups.create
      group.add_user(user1)
      expect(group).to have_common_section_with_user(user2)
    end

    it "is true if one member is inactive" do
      course_with_teacher(active_all: true)
      section1 = @course.course_sections.create
      user1 = section1.enroll_user(user_model, "StudentEnrollment").user
      user2 = section1.enroll_user(user_model, "StudentEnrollment").user
      group = @course.groups.create
      group.add_user(user1)
      e = Enrollment.where(user_id: user1.id, course_id: @course.id)
      e.update(workflow_state: "inactive")
      group.add_user(user2)
      expect(group).to have_common_section_with_user(user2)
    end

    it "is true if one member is completed" do
      course_with_teacher(active_all: true)
      section1 = @course.course_sections.create
      user1 = section1.enroll_user(user_model, "StudentEnrollment").user
      user2 = section1.enroll_user(user_model, "StudentEnrollment").user
      group = @course.groups.create
      group.add_user(user1)
      Enrollment.where(user_id: user1.id, course_id: @course.id).update(workflow_state: "completed")
      group.add_user(user2)
      expect(group).to have_common_section_with_user(user2)
    end
  end

  context "tabs_available" do
    before :once do
      course_with_teacher(active_course: true)
      @teacher = @user
      @group = group(group_context: @course)
      @group.users << @student = student_in_course(course: @course).user
    end

    describe "TAB_CONFERENCES" do
      context "when WebConferences are enabled" do
        before do
          allow(WebConference).to receive(:plugins).and_return(
            [
              web_conference_plugin_mock("big_blue_button", { domain: "bbb.instructure.com", secret_dec: "secret" }),
              web_conference_plugin_mock("wimba", { domain: "wimba.test" }),
              web_conference_plugin_mock("broken_plugin", { foor: :bar })
            ]
          )
        end

        it "returns the plugin names" do
          tabs = @group.tabs_available(@user)
          expect(tabs.find { |t| t[:css_class] == "conferences" }[:label]).to eq("Big blue button Wimba")
        end
      end

      context "when WebConferences are not enabled" do
        it "returns Conferences" do
          tabs = @group.tabs_available(@user)
          expect(tabs.find { |t| t[:css_class] == "conferences" }[:label]).to eq("Conferences")
        end
      end
    end

    it "lets members see everything" do
      expect(@group.tabs_available(@student).pluck(:id)).to eql [
        Group::TAB_HOME,
        Group::TAB_ANNOUNCEMENTS,
        Group::TAB_PAGES,
        Group::TAB_PEOPLE,
        Group::TAB_DISCUSSIONS,
        Group::TAB_FILES,
        Group::TAB_CONFERENCES,
        Group::TAB_COLLABORATIONS,
        Group::TAB_COLLABORATIONS_NEW
      ]
    end

    it "lets admins see everything" do
      expect(@group.tabs_available(@teacher).pluck(:id)).to eql [
        Group::TAB_HOME,
        Group::TAB_ANNOUNCEMENTS,
        Group::TAB_PAGES,
        Group::TAB_PEOPLE,
        Group::TAB_DISCUSSIONS,
        Group::TAB_FILES,
        Group::TAB_CONFERENCES,
        Group::TAB_COLLABORATIONS,
        Group::TAB_COLLABORATIONS_NEW
      ]
    end

    it "does not let nobodies see conferences" do
      expect(@group.tabs_available(nil).pluck(:id)).not_to include Group::TAB_CONFERENCES
    end
  end

  describe "quota" do
    it "defaults to Group.default_storage_quota" do
      expect(@group.quota).to eq Group.default_storage_quota
    end

    it "is overridden by the account's default_group_storage_quota" do
      a = @group.account
      a.default_group_storage_quota = 10.decimal_megabytes
      a.save!

      @group.reload
      expect(@group.quota).to eq 10.decimal_megabytes
    end

    it "inherits from a parent account's default_group_storage_quota" do
      enable_cache do
        account = account_model
        subaccount = account.sub_accounts.create!

        account.default_group_storage_quota = 10.decimal_megabytes
        account.save!

        course_factory(account: subaccount)
        @group = group(group_context: @course)

        expect(@group.quota).to eq 10.decimal_megabytes

        # should reload
        account.default_group_storage_quota = 20.decimal_megabytes
        account.save!
        @group = Group.find(@group.id)

        expect(@group.quota).to eq 20.decimal_megabytes
      end
    end
  end

  describe "#update_max_membership_from_group_category" do
    it "sets max_membership if there is a group category" do
      @group.group_category = @course.group_categories.build(name: "foo")
      @group.group_category.group_limit = 1
      @group.update_max_membership_from_group_category
      expect(@group.max_membership).to eq 1
    end

    it "does nothing if there is no group category" do
      expect(@group.max_membership).to be_nil
      @group.update_max_membership_from_group_category
      expect(@group.max_membership).to be_nil
    end
  end

  describe "#destroy" do
    before :once do
      @gc = GroupCategory.create! name: "groups", course: @course
      @group = @gc.groups.create! name: "group1", context: @course
    end

    it "softs delete" do
      expect(@group.deleted_at).to be_nil
      @group.destroy
      expect(@group.deleted_at).not_to be_nil
    end

    it "does not delete memberships" do
      student_in_course active_all: true
      @group.users << @student
      @group.save!

      expect(@group.users).to eq [@student]
      @group.destroy
      expect(@group.users.reload).to eq [@student]
    end
  end

  describe "includes_user?" do
    before do
      user_model
      pseudonym_model(user_id: @user.id)
    end

    it "returns true if a user is in the group" do
      @group.add_user(@user)
      expect(@group.includes_user?(@user)).to be_truthy
    end

    it "returns false if the user is not in the group" do
      expect(@group.includes_user?(@user)).to be_falsey
    end

    it "returns false if no user object is given" do
      expect(@group.includes_user?(nil)).to be_falsey
    end

    it "returns false if an unsaved user is given" do
      @user = User.new
      expect(@group.includes_user?(@user)).to be_falsey
    end
  end

  describe "#favorite_for_user?" do
    before do
      context = course_model
      @group_fave = Group.create!(name: "group1", context:)
      @group_not_fave = Group.create!(name: "group2", context:)
      @group_fave.add_user(@user)
      @group_not_fave.add_user(@user)
      @user.favorites.build(context: @group_fave)
      @user.save
    end

    it "returns true if a user has a course set as a favorite" do
      expect(@group_fave.favorite_for_user?(@user)).to be(true)
    end

    it "returns false if a user has not set a group to be a favorite" do
      expect(@group_not_fave.favorite_for_user?(@user)).to be(false)
    end
  end

  describe "submissions_folder" do
    it "creates the root submissions folder on demand" do
      f = @group.submissions_folder
      expect(@group.submissions_folders.where(parent_folder_id: Folder.root_folders(@group).first, name: "Submissions").first).to eq f
    end

    it "finds the existing root submissions folder" do
      f = @group.folders.build
      f.parent_folder_id = Folder.root_folders(@group).first
      f.name = "blah"
      f.submission_context_code = "root"
      f.save!
      expect(@group.submissions_folder).to eq f
    end
  end

  describe "participating_users_in_context" do
    before :once do
      context = course_model
      @group = Group.create(name: "group1", context:)
      @group.add_user(@user)
      @user.enrollments.first.deactivate
    end

    it "filter inactive users if requested" do
      users = @group.participating_users_in_context
      expect(users.length).to eq 0
    end

    it "don't filter inactive users if not requested" do
      users = @group.participating_users_in_context(include_inactive_users: true)
      expect(users.length).to eq 1
      expect(users.first.id).to eq @user.id
    end
  end

  describe "usage_rights_required" do
    it "returns true on course group" do
      @course.update!(usage_rights_required: true)
      expect(@group.usage_rights_required?).to be true
    end

    it "returns true on account group" do
      account = account_model
      account.settings = { "usage_rights_required" => {
        "value" => true
      } }
      group = group_model(context: account)
      expect(group.usage_rights_required?).to be true
    end
  end

  describe ".ids_by_student_by_assignment" do
    it "returns a hash of assignment_id => user_id => group_id" do
      first_student = @course.enroll_student(user_model, enrollment_state: "active").user
      second_student = @course.enroll_student(user_model, enrollment_state: "active").user

      first_group = @group
      group_category = first_group.group_category
      first_group.add_user(first_student)
      second_group = @course.groups.create!(group_category:)
      second_group.add_user(second_student)
      assignment = @course.assignments.create!(group_category:)

      aggregate_failures do
        map = Group.ids_by_student_by_assignment([first_student.id], [assignment.id])
        expect(map.dig(assignment.id, first_student.id)).to eq first_group.id
        expect(map.fetch(assignment.id)).not_to have_key(second_student.id)

        map = Group.ids_by_student_by_assignment([first_student.id, second_student.id], [assignment.id])
        expect(map.dig(assignment.id, first_student.id)).to eq first_group.id
        expect(map.dig(assignment.id, second_student.id)).to eq second_group.id

        expect(Group.ids_by_student_by_assignment([first_student.id], [])).to be_empty
      end
    end
  end

  describe "non_collaborative groups" do
    before do
      @course = Course.create!(name: "Test Course")
      @teacher = User.create!(name: "Teacher")
      @student = User.create!(name: "Student")
      teacher_in_course(course: @course, user: @teacher, active_all: true)
      student_in_course(course: @course, user: @student, active_all: true)

      @non_collaborative_category = GroupCategory.create!(name: "Non-Collaborative Category", context: @course, non_collaborative: true)
      @collaborative_category = GroupCategory.create!(name: "Collaborative Category", context: @course, non_collaborative: false)
    end

    it "can filter out collaborative and noncollaborative groups" do
      non_collaborative_group = Group.create(context: @course, group_category: @non_collaborative_category, name: "Non-Collaborative Group")
      collaborative_group = Group.create(context: @course, group_category: @collaborative_category, name: "Collaborative Group")

      expect(Group.non_collaborative).to eq [non_collaborative_group]
      expect(Group.collaborative).to include(collaborative_group)
      expect(Group.collaborative).not_to include(non_collaborative_group)
    end

    it "non_collaborative can be set on creation but cannot be changed afterwards" do
      # Set non_collaborative on creation
      group = Group.create(context: @course, group_category: @non_collaborative_category, name: "Test Group")
      expect(group).to be_valid
      expect(group.non_collaborative).to be true

      # Attempt to change non_collaborative
      group.non_collaborative = false
      group.save
      expect(group.reload.non_collaborative).to be true

      # Attempt to change non_collaborative using update
      group.update(non_collaborative: false)
      expect(group.reload.non_collaborative).to be true

      # Create a group without setting non_collaborative
      another_group = Group.create(context: @course, group_category: @collaborative_category, name: "Another Test Group")
      expect(another_group).to be_valid
      expect(another_group.non_collaborative).to be false

      # Attempt to set non_collaborative after creation
      another_group.non_collaborative = true
      another_group.save
      expect(another_group.reload.non_collaborative).to be false
    end

    it "must belong to a course" do
      course_group = Group.new(context: @course, group_category: @non_collaborative_category, name: "Course Group")
      expect(course_group).to be_valid

      account_group = Group.new(context: @account, group_category: @non_collaborative_category, name: "Account Group")
      expect(account_group).not_to be_valid
      expect(account_group.errors[:base]).to include("Non-collaborative groups must belong to a course")
    end

    it "cannot have a leader" do
      group_with_leader = Group.new(context: @course, group_category: @non_collaborative_category, name: "Group with Leader", leader: @student)
      expect(group_with_leader).not_to be_valid
      expect(group_with_leader.errors[:base]).to include("Non-collaborative groups cannot have a leader")

      group_without_leader = Group.new(context: @course, group_category: @non_collaborative_category, name: "Group without Leader")
      expect(group_without_leader).to be_valid
    end

    it "must match the non_collaborative status of its category" do
      mismatched_group = Group.new(context: @course, name: "Mismatched Group", group_category: @collaborative_category, non_collaborative: true)
      expect(mismatched_group).not_to be_valid
      expect(mismatched_group.errors[:base]).to include("Group non_collaborative status must match its category")

      matched_group = Group.new(context: @course, name: "Matched Group", group_category: @non_collaborative_category, non_collaborative: true)
      expect(matched_group).to be_valid
    end

    it "sets non_collaborative to true if the group_category is non_collaborative" do
      group = Group.create!(name: "Non-Collaborative Group", group_category: @non_collaborative_category, context: @course)
      expect(group.non_collaborative).to be_truthy
    end

    it "sets non_collaborative to false if the group_category is collaborative" do
      group = Group.create!(name: "Collaborative Group", group_category: @collaborative_category, context: @course)
      expect(group.non_collaborative).to be_falsey
    end

    context "permissions" do
      before do
        @group = Group.create!(context: @course, group_category: @non_collaborative_category, name: "Test Group", non_collaborative: true)
        @course.account.enable_feature! :assign_to_differentiation_tags
        @course.account.settings[:allow_assign_to_differentiation_tags] = { value: true }
        @course.account.save!
        @course.account.reload
        allow(@course).to receive(:grants_any_right?).with(@teacher, anything, *RoleOverride::GRANULAR_MANAGE_TAGS_PERMISSIONS).and_return(true)
      end

      it "grants correct permissions to default teachers in non-collaborative groups" do
        expect(@group.check_policy(@teacher)).to include(
          :read,
          :read_roster,
          :read_files,
          :send_messages,
          :send_messages_all,
          :manage,
          :allow_course_admin_actions,
          :manage_students,
          :update,
          :read_as_admin,
          :read_sis,
          :view_user_logins,
          :read_email_addresses,
          :delete,
          :create
        )
      end

      it "checks send_messages permission correctly" do
        allow(@course).to receive(:grants_right?).and_return(true)
        allow(@course).to receive(:grants_right?).with(@teacher, anything, :send_messages).and_return(false)
        expect(@group.check_policy(@teacher)).not_to include(:send_messages)
      end

      it "checks send_messages_all permission correctly" do
        allow(@course).to receive(:grants_right?).and_return(true)
        allow(@course).to receive(:grants_right?).with(@teacher, anything, :send_messages_all).and_return(false)
        expect(@group.check_policy(@teacher)).not_to include(:send_messages_all)
      end

      it "checks update and manage permissions correctly" do
        allow(@course).to receive(:grants_right?).and_return(true)
        allow(@course).to receive(:grants_right?).with(anything, anything, :manage_tags_manage).and_return(false)

        expect(@group.check_policy(@teacher)).not_to include(:manage, :update, :allow_course_admin_actions, :manage_students)
      end

      it "checks delete permission correctly" do
        allow(@course).to receive(:grants_right?).and_return(true)
        allow(@course).to receive(:grants_right?).with(@teacher, anything, :manage_tags_delete).and_return(false)
        expect(@group.check_policy(@teacher)).not_to include(:delete)
      end

      it "checks create permission correctly" do
        allow(@course).to receive(:grants_right?).and_return(true)
        allow(@course).to receive(:grants_right?).with(@teacher, anything, :manage_tags_add).and_return(false)
        expect(@group.check_policy(@teacher)).not_to include(:create)
      end

      it "does not grant permissions to users without manage_groups or manage_groups_manage" do
        user = User.create!(name: "Random User")
        expect(@group.check_policy(user)).to be_empty
      end

      it "does not grant permissions to a student" do
        expect(@group.check_policy(@student)).to be_empty
      end

      it "does not grant permissions to a student who is a group member" do
        @group.add_user(@student)
        expect(@group.reload.check_policy(@student)).to be_empty
      end
    end

    context "differentiation tag validations" do
      before do
        @c1 = GroupCategory.where(non_collaborative: true).last
        @c2 = GroupCategory.create!(context: @course, name: "Category 2", non_collaborative: true)
        @c3 = GroupCategory.create!(context: @course, name: "Category 3", non_collaborative: true)
        @c4 = GroupCategory.create!(context: @course, name: "Category 4", non_collaborative: true)
        10.times do |i|
          Group.create!(context: @course, group_category: @c1, name: "Group #{i}", non_collaborative: true)
          Group.create!(context: @course, group_category: @c2, name: "Group #{i + 10}", non_collaborative: true)
          Group.create!(context: @course, group_category: @c3, name: "Group #{i + 20}", non_collaborative: true)
          Group.create!(context: @course, group_category: @c4, name: "Group #{i + 30}", non_collaborative: true)
        end
        @course.account.settings[:allow_assign_to_differentiation_tags] = { value: true }
        @course.account.save!
        @course.account.reload
      end

      it "reaching the tag limit and removing a tag allows to create another" do
        expect(@c4.max_diff_tag_validation_count).to eq GroupCategory.MAX_DIFFERENTIATION_TAG_PER_COURSE

        Group.where(group_category: @c4).last.delete
        group = Group.create!(context: @course, group_category: @c4, name: "Group 40", non_collaborative: true)

        expect(group).to be_valid
        expect(group.errors).to be_empty
      end

      it "does not allow to create a tag variant after the limit" do
        expect(@c4.max_diff_tag_validation_count).to eq GroupCategory.MAX_DIFFERENTIATION_TAG_PER_COURSE

        Group.where(group_category: @c3).last.delete
        group = Group.create(context: @course, group_category: @c4, name: "Group 40", non_collaborative: true)

        expect(group).not_to be_valid
        expect(group.errors[:base]).to include("Variant limit reached for tag")
      end

      it "leaves out soft deleted tags" do
        expect(@c4.max_diff_tag_validation_count).to eq GroupCategory.MAX_DIFFERENTIATION_TAG_PER_COURSE
        GroupCategory.last.update(deleted_at: Time.zone.now)
        # Each group category has 10 groups so setting a category as deleted will reduce the count by 10
        expect(@c4.max_diff_tag_validation_count).to eq 30

        tag = GroupCategory.create(context: @course, name: "Category 5", non_collaborative: true)
        expect(tag).to be_valid
        expect(tag.errors).to be_empty
      end
    end
  end
end
