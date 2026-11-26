# Beeper's brand as the admin theme's starting point (the upstream defaults are
# a neutral indigo). Only column defaults change: a theme row someone already
# saved keeps its values, and Configuration > Theme can still change them all.
class SetBeeperAdminThemeDefaults < ActiveRecord::Migration[6.1]
  BEEPER = {
    brand_name: ['Admin', 'Beeper'],
    primary_color: ['#6366f1', '#900093'],
    secondary_color: ['#8b5cf6', '#ff008a'],
    surface_color: ['#1a1a2e', '#1d0b2b'],
    background_color: ['#0f0f1a', '#14001f'],
    text_color: ['#e2e8f0', '#f5f3f7'],
    sidebar_color: ['#16162a', '#170823']
  }.freeze

  def change
    BEEPER.each do |column, (from, to)|
      change_column_default :admin_themes, column, from: from, to: to
    end
  end
end
