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

import React from 'react'
import {fireEvent, render} from '@testing-library/react'
import {ContextModuleProvider, contextModuleDefaultProps} from '../../hooks/useModuleContext'
import ModuleItemActionMenu from '../ModuleItemActionMenu'

const setUp = (itemType: string = 'Assignment') => {
  const container = render(
    <ContextModuleProvider {...contextModuleDefaultProps}>
      <ModuleItemActionMenu
        itemType={itemType}
        canDuplicate={true}
        isMenuOpen={false}
        setIsMenuOpen={() => {}}
        indent={1}
        handleEdit={() => {}}
        handleSpeedGrader={() => {}}
        handleAssignTo={() => {}}
        handleDuplicate={() => {}}
        handleMoveTo={() => {}}
        handleDecreaseIndent={() => {}}
        handleIncreaseIndent={() => {}}
        handleSendTo={() => {}}
        handleCopyTo={() => {}}
        handleRemove={() => {}}
        masteryPathsData={{
          isCyoeAble: false,
          isTrigger: false,
          isReleased: false,
          releasedLabel: null,
        }}
        handleMasteryPaths={() => {}}
      />
    </ContextModuleProvider>,
  )

  const menuButton = container.getByTestId('module-item-action-menu-button')
  return {container, menuButton}
}

const assertMenuItems = ({
  itemType,
  visibleItems = [],
  hiddenItems = [],
}: {
  itemType: string
  visibleItems: string[]
  hiddenItems: string[]
}) => {
  const {container, menuButton} = setUp(itemType)
  fireEvent.click(menuButton)

  for (const text of visibleItems) {
    expect(container.getByText(text)).toBeInTheDocument()
  }

  for (const text of hiddenItems) {
    expect(container.queryByText(text)).not.toBeInTheDocument()
  }
}

describe('ModuleItemActionMenu', () => {
  it('renders action menu correctly', () => {
    const {container} = setUp()
    expect(container.container).toBeInTheDocument()
  })

  it('renders menu with correct props for default itemType', () => {
    assertMenuItems({
      itemType: 'Assignment',
      visibleItems: [
        'Edit',
        'SpeedGrader',
        'Assign To...',
        'Duplicate',
        'Move to...',
        'Decrease indent',
        'Increase indent',
        'Send To...',
        'Copy To...',
        'Remove',
      ],
      hiddenItems: [],
    })
  })

  it('renders menu for basic content types like SubHeader', () => {
    assertMenuItems({
      itemType: 'SubHeader',
      visibleItems: ['Edit', 'Move to...', 'Decrease indent', 'Increase indent', 'Remove'],
      hiddenItems: [
        'SpeedGrader',
        'Assign To...',
        'Duplicate',
        'Send To...',
        'Copy To...',
        'Add Mastery Paths',
        'Edit Mastery Paths',
      ],
    })
  })

  it.each([['File'], ['ExternalTool']])('hides specific menu items for %s itemType', itemType => {
    assertMenuItems({
      itemType,
      visibleItems: ['Edit', 'Move to...', 'Decrease indent', 'Increase indent', 'Remove'],
      hiddenItems: [
        'SpeedGrader',
        'Assign To...',
        'Duplicate',
        'Send To...',
        'Copy To...',
        'Add Mastery Paths',
        'Edit Mastery Paths',
      ],
    })
  })
})
