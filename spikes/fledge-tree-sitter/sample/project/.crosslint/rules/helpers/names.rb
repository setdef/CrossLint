# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT

module Names
  def self.component?(name) = name.to_s.end_with?("Component")
end
