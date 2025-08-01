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

module Api::V1::Admin
  include Api::V1::Json
  include Api::V1::User

  def admin_json(admin, current_user, session, includes = [])
    # admin is an AccountUser
    {
      id: admin.id,
      role: admin.role.name,
      role_id: admin.role_id,
      user: user_json(admin.user, current_user, session, includes),
      workflow_state: admin.workflow_state
    }
  end
end
