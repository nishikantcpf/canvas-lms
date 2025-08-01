/*
 * Copyright (C) 2025 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {View} from '@instructure/ui-view'
import {BaseBlock} from '../BaseBlock'
import {useScope as createI18nScope} from '@canvas/i18n'
import {BorderWidth, BorderWidthValues} from '@instructure/emotion'

export type SeparatorLineBlockProps = {
  thickness: BorderWidthValues
}

export const SeparatorLineBlockContent = (props: SeparatorLineBlockProps) => {
  const borderWidth: BorderWidth = `0 0 ${props.thickness} 0`

  return <View as="hr" data-testid="separator-line" borderWidth={borderWidth} />
}

const I18n = createI18nScope('page_editor')

export const SeparatorLineBlock = (props: SeparatorLineBlockProps) => {
  return (
    <BaseBlock title={I18n.t('Separator line')}>
      <SeparatorLineBlockContent {...props} />
    </BaseBlock>
  )
}
