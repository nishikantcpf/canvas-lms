# frozen_string_literal: true

#
# Copyright (C) 2021 - present Instructure, Inc.
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

module ObserverEnrollmentsHelper
  include Api::V1::User

  MAX_OBSERVED_USERS = 1000
  OBSERVER_COOKIE_PREFIX = "k5_observed_user_for_"

  # Returns users whom the user is observing. Sorted by sortable_name. Includes the
  # provided user first if they have their own non-ObserverEnrollment enrollments or
  # ObserverEnrollments without an associated_user_id. Uses all enrollments if course_id
  # is nil, otherwise restricts results to provided course.
  def observed_users(user, session, course_id = nil)
    return [] unless user

    users = Rails.cache.fetch_with_batched_keys(["observed_users2", course_id].cache_key, batch_object: user, batched_keys: :enrollments, expires_in: 1.day) do
      GuardRail.activate(:secondary) do
        scope = user.enrollments.active_or_pending_by_date
        scope = if course_id
                  scope.shard(Shard.shard_for(course_id)).where(course_id:)
                else
                  scope.shard(user.in_region_associated_shards)
                end
        has_own_enrollments = scope.not_of_observer_type.exists? || scope.of_observer_type.where(associated_user_id: nil).exists?
        users = User.where(
          id: scope.of_observer_type.where.not(associated_user_id: nil).distinct.limit(MAX_OBSERVED_USERS).pluck(:associated_user_id)
        ).sort_by { |u| Canvas::ICU.collation_key(u.sortable_name) }.to_a
        users.prepend(user) if has_own_enrollments
        users
      end
    end

    observed_user_cookie_name = "#{OBSERVER_COOKIE_PREFIX}#{user.id}"
    @selected_observed_user = users.detect { |u| u.id.to_s == cookies[observed_user_cookie_name] } || users.first
    cookies.delete(observed_user_cookie_name) if @selected_observed_user == users.first
    users.map { |u| user_json(u, @current_user, session, ["avatar_url"], @context, nil, ["pseudonym"]) }
  end

  # Helper method for GraphQL loaders to determine which observed student is currently selected
  # based on the observer cookie mechanism
  def selected_observed_student_from_cookie(current_user, observed_students, request)
    return observed_students.first if observed_students.empty? || current_user.nil?

    # Use the observer cookie mechanism to determine which student is currently selected
    observed_user_cookie_name = "#{OBSERVER_COOKIE_PREFIX}#{current_user.id}"

    # Get cookies from request if available
    selected_user_id = request&.cookies&.[](observed_user_cookie_name)

    # Find the selected student from observed students, or fall back to first
    if selected_user_id
      selected_student = observed_students.find { |student| student.id.to_s == selected_user_id.to_s }
      return selected_student if selected_student
    end

    # Default to first observed student
    observed_students.first
  end
end
