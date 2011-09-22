# -*- coding: utf-8 -*-
module ApplicationHelper
  MANAGE_PAGES = %w(users clients projects roles activity_types activity_custom_properties currencies settings)

  def format_minutes(minutes)
    return "0" unless minutes
    format("%d:%.2d", minutes / 60, minutes % 60)
  end

  def site_url
    Rubytime::CONFIG[:site_url]
  end

  def activity_type_select(obj)
    types = if obj.is_a?(Project)
              obj.available_activity_types
            else
              obj.project && obj.project.available_activity_types || []
            end
    
    selected = obj.activity_type_id if obj.is_a?(Activity)
    
    list = types.map do |main_type|
      data = [[main_type[:id], main_type[:name]]]
      data += main_type[:available_subactivity_types].map { |st| [st[:id], "– " + st[:name]] }
      data
    end
    
    select :name => 'activity_type_id', :collection => list.inject(&:+), :selected => selected
  end

  def main_menu_items 
    return [] unless current_user
    main_menu = []
    
    selected = controller_name == 'activities'
    main_menu << { :title => "Activities", :path => activities_path, :selected => selected }
    
    if current_user.is_client_user?
      selected = (controller_name == 'projects' && action_name == 'index' )
      main_menu << { :title => "Projects", :path => projects_path, :selected => selected }
    end

    if current_user.is_admin? || current_user.is_client_user?
      selected = controller_name == 'invoices'
      main_menu << { :title => "Invoices", :path => invoices_path, :selected => selected }
    end
    
    if current_user.is_admin?
      selected = MANAGE_PAGES.include?(controller_name)
      main_menu << { :title => "Manage", :path => users_path, :selected => selected }
    end
    
    main_menu
  end
  
  def sub_menu_items
    sub_menu = []
    case controller_name
    when *MANAGE_PAGES
      if current_user.is_admin?
        sub_menu << { :title => "Users", :path => users_path, :selected => controller_name == 'users' }
        sub_menu << { :title => "Clients", :path => clients_path, :selected => controller_name == 'clients' }
        sub_menu << { :title => "Projects", :path => projects_path, :selected => controller_name == 'projects' }
        sub_menu << { :title => "Roles", :path => roles_path, :selected => controller_name == 'roles' }
        sub_menu << { :title => "Activity types", :path => activity_types_path, :selected => controller_name == 'activity_types' }
        sub_menu << { :title => "Custom activity properties", :path => activity_custom_properties_path, :selected => controller_name == 'activity_custom_properties' }
        sub_menu << { :title => "Currencies", :path => currencies_path, :selected => controller_name == 'currencies' }
        sub_menu << { :title => "Settings", :path => edit_settings_path, :selected => controller_name == 'settings' }
      end
    when 'invoices'
      sub_menu << { :title => "All", :path => invoices_path, :selected => params[:filter].nil? }
      sub_menu << { :title => "Issued", :path => issued_invoices_path, :selected => params[:filter] == 'issued' }
      sub_menu << { :title => "Pending", :path => pending_invoices_path, :selected => params[:filter] == 'pending' }
    when 'activities'
      if current_user.is_employee?
        sub_menu << { :title => "List", :path => activities_path, :selected => action_name == 'index' }
        sub_menu << { :title => "Calendar", :path => user_calendar_path(current_user.id), :selected => action_name == 'calendar' }
      end
    end
    sub_menu
  end
  
  def unique_clients_from(activities)
    activities.map(&:project).map(&:client).uniq.sort_by(&:name)
  end
  
  def unique_projects_from(activities, client)
    activities.select { |a| a.project.client_id == client.id }.map(&:project).uniq.sort_by(&:name)
  end
  
  def unique_roles_from(activities, client, project)
    activities.select { |a| a.project_id == project.id }.map(&:role).uniq.sort_by(&:name)
  end
  
  def activities_from(activities, client, project = nil, role = nil)
    activities = activities.select { |a| a.project.client_id == client.id }
    if project
      activities = activities.select { |a| a.project_id == project.id }
      activities = activities.select { |a| a.role_id == role.id } if role
    end
    activities.sort_by(&:date)
  end
  
  def total_from(activities)
    format_minutes(activities.inject(0) { |a,act| a + act.minutes })
  end
  
  def total_custom_properties(activities, client, project=nil, role=nil)
    html = ""
    @custom_properties.each do |activity_custom_property|
      html << %(<p>)
      html << %(Total #{activity_custom_property.name}: )
      html << %(#{format_number(Activity.custom_property_values_sum(activities_from(activities, client, project, role), activity_custom_property))})
      html << %( #{activity_custom_property.unit})
      html << %(</p>)
    end
    html
  end
  
  def activities_table(activities, options={})
    default_options = { 
      :show_checkboxes => false, 
      :show_users => true, 
      :show_details_link => true, 
      :show_edit_link => true,
      :show_delete_link => true, 
      :show_exclude_from_invoice_link => false, 
      :expanded => false, 
      :show_date => true,
      :custom_properties_to_show_in_columns => @column_properties,
      :custom_properties_to_show_in_expanded_view => @non_column_properties
    }

    options = default_options.merge(options)

    table_opts = { :class => 'activities list wide', :id => "#{options[:table_id]}"}
    table_opts.reject!{|k,v| v.blank?}

    html = %(#{tag(:table, table_opts, true)})
    html <<  %(<tr>)
    html << %(<th class="checkbox">#{check_box_tag 'all', "1", false, :class => "activity_select_all"}</th>) if options[:show_checkboxes]
    html << %(<th>#{image_tag("icons/project.png", :alt => 'project') if options[:show_header_icons]} Project</th>) if options[:show_project]
    html << %(<th>#{image_tag("icons/role.png", :alt => 'role') if options[:show_header_icons]} User</th>) if options[:show_users]
    html << %(<th>Date</th>) if options[:show_date]
    html << %(<th class="right">#{image_tag("icons/clock.png", :alt => 'clock') if options[:show_header_icons]} Hours</th>)
    
    options[:custom_properties_to_show_in_columns].each do |custom_property|
      html << %(<th class="right">#{custom_property.name_with_unit}</th>)
    end
    
    html << %(<th class="icons">)
    html << link_to(image_tag("icons/magnifier.png", :title => "Toggle all details", :alt => 'I'), "#", :class => "toggle_all_comments_link") if options[:show_details_link]
    html << %(</th>)
    html << %(</tr>)
    activities.each do |activity|
      html << activities_table_row(activity, options)
    end
    html << %(<tr class="no_zebra">)
    html << %(<td></td>) if options[:show_checkboxes]
    html << %(<td></td>) if options[:show_project]
    html << %(<td></td>) if options[:show_users]
    html << %(<td class="right"><strong>Total:</strong></td>)
    html << %(<td class="right"><strong>#{total_from(activities)}</strong></td>)
    options[:custom_properties_to_show_in_columns].each do |custom_property|
      html << %(<td class="right"><strong>#{format_number(Activity.custom_property_values_sum(activities, custom_property))}</strong></td>)
    end
    html << %(<td></td>)
    html << %(</tr>)
    html << %(</table>)

    html.html_safe
  end

  def activities_table_row(activity, options)
    row = %(<tr>)
    if options[:show_checkboxes]
      row << %(<td class="checkbox">#{check_box_tag("activity_id[]", activity.id, false, :id => "activity_id_#{activity.id}", :class => "checkbox") unless activity.invoiced?}</td>)
    end
    row << %(<td>#{h(activity.project.name)}</td>) if options[:show_project]
    row << %(<td>#{h(activity.user.name)}</td>) if options[:show_users]
    row << %(<td>#{activity.date.formatted(current_user.date_format)}</td>) if options[:show_date]
    row << %(<td class="right">#{activity.hours}</td>)
    
    options[:custom_properties_to_show_in_columns].each do |custom_property|
      row << %(<td class="right">#{format_number(activity.custom_properties[custom_property.id])}</td>)
    end

    # icons
    row << %(<td class="icons">)
    row << link_to(image_tag("icons/magnifier.png", :alt => "I", :title => "Toggle details"), "#", :class => "toggle_comments_link") if options[:show_details_link]
    row << link_to(image_tag("icons/pencil.png", :alt => "E", :title => "Edit"), edit_activity_path(activity)+"?height=400&amp;width=500", :class => "edit_activity_link", :title => "Editing activity") if options[:show_edit_link] && activity.deletable_by?(current_user) && !activity.locked?
    row << link_to(image_tag("icons/cross.png", :alt => "R", :title => "Remove"), activity_path(activity), :class => "remove_activity_link") if options[:show_delete_link] && activity.deletable_by?(current_user) && !activity.locked?
    row << link_to(image_tag("icons/notebook_minus.png", :alt => "-", :title => "Remove activity from this invoice"), activity_path(activity), :class => "remove_from_invoice_link") if options[:show_exclude_from_invoice_link] && !activity.locked?
    row << %(</td>)

    klass, visibility = (options[:expanded] ? ["", ""] : ["no_zebra", "display: none"])
    row << %(</tr><tr class="comments #{klass}" style="#{visibility}"><td colspan="#{options[:custom_properties_to_show_in_columns].size + 5}">)
    row << %(<p><strong>#{h(activity.breadcrumb_name)}</strong></p>) if activity.breadcrumb_name
    options[:custom_properties_to_show_in_expanded_view].each do |custom_property|
      if activity.custom_properties[custom_property.id]
        row << %(<p><strong>#{custom_property.name}</strong>: #{format_number(activity.custom_properties[custom_property.id])} #{custom_property.unit}</p>)
      end
    end
    row << %(<p>#{h(activity.comments).gsub(/\n/, "<br/>")}</p></td></tr>)
    row    
  end

  def full_activities_table(activities)
    activities_table(activities, :show_checkboxes => current_user.is_admin?,
                     :show_users => current_user.is_admin? || !current_user.is_employee?,
                     :show_details_link => true, :show_edit_link => true,
                     :show_delete_link => true, :show_exclude_from_invoice_link => false)
  end

  def invoice_activities_table(activities, options={})
    activities_table(activities, { :show_checkboxes => false, :show_users => true, :show_details_link => true,
                       :show_edit_link => false, :show_delete_link => false,
                       :show_exclude_from_invoice_link => current_user.is_admin? }.merge!(options))
  end

  def calendar_activities_table(activities, options={})
    activities_table(activities, { :show_checkboxes => false, :show_users => current_user.is_admin? || !current_user.is_employee?,
                       :show_details_link => false, :show_edit_link => true, :show_delete_link => false,
                       :show_project => true, :expanded => true, :show_date => false }.merge!(options))
  end

  def role_options_for_hourly_rate
    Role.all.map { |role| [role.id, role.name] }
  end

  def currency_options_for_hourly_rate
    select_options(Currency.all, :id, :plural_name)
  end

  def decimal_separator
    current_user ? current_user.decimal_separator : Rubytime::DECIMAL_SEPARATORS.first
  end

  def format_number(number, options = {})
    return if number.nil?

    if options.has_key?(:precision)
      number_with_precision(Rubytime::DECIMAL_FORMATS[decimal_separator].merge(options))
    else
      number_with_delimiter(Rubytime::DECIMAL_FORMATS[decimal_separator].merge(options))
    end
  end

  def smart_errors_format(errors)
    message = errors.full_messages.reject { |m| m =~ /integer/ }.join(", ").split(' ')
    message.first.capitalize unless message.empty?
    message.join(' ')
  end

  def auto_link
    file = params[:controller].to_s.gsub("/", "") + ".js"
    if File.exist?(File.join(Rails.root, "/public/javascripts/", file))
      javascript_include_tag(file)
    end
  end

  def select_options(collection, value_method, text_method, selected = nil)
    options_from_collection_for_select(collection, value_method, text_method, selected)
  end
end
