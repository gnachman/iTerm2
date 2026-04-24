//
//  iTermTerminfo.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/16/24.
//

#import "iTermTerminfo.h"

#import "DebugLogging.h"
#import "iTermTerminfoHelper.h"

#import <term.h>
#import <curses.h>


@implementation iTermTerminfo {
    NSDictionary<NSString *, id> *_database;
}

+ (instancetype)forTerm:(NSString *)term {
    static NSMutableDictionary *terms;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        terms = [NSMutableDictionary dictionary];
    });
    @synchronized (self) {
        id instance = terms[term];
        if (!instance) {
            instance = [[iTermTerminfo alloc] initWithTerm:term];
            terms[term] = instance;
        }
        return instance;
    }
}

- (instancetype)initWithTerm:(NSString *)term {
    self = [super init];
    if (self) {
        _term = [term copy];
        _database = [self computeDatabase];
    }
    return self;
}

- (BOOL)isValid {
    return _database != nil;
}

- (id)sync:(id (^NS_NOESCAPE)(void))block {
    static dispatch_queue_t _queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _queue = dispatch_queue_create("com.googlecode.iterm2.terminfo", DISPATCH_QUEUE_SERIAL);
    });
    __block id value = nil;
    dispatch_sync(_queue, ^{
        value = block();
    });
    return value;
}

- (NSDictionary<NSString *, id> *)computeDatabase {
    return [self sync:^id {
        char *term = strdup(_term.UTF8String);
        int ignored = 0;
        if (setupterm(term, 1, &ignored) != OK || cur_term == NULL) {
            DLog(@"Failed to compute terminfo database for \(term)");
            free(term);
            return nil;
        }

        NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
        struct termtype *termType = &cur_term->type;
        for (int i = 0; i < iTermTerminfoNumberOfStrings(termType); i++) {
            char *keycstr = iTermTerminfoStringName(termType, i);
            char *valuecstr = tigetstr(keycstr);
            if (valuecstr != NULL && valuecstr != (char *)-1) {
                NSString *key = [NSString stringWithCString:keycstr encoding:NSUTF8StringEncoding];
                NSString *value = [NSString stringWithCString:valuecstr encoding:NSUTF8StringEncoding];
                result[key] = value;
            }
        }
        for (int i = 0; i < iTermTerminfoNumberOfBooleans(termType); i++) {
            char *keycstr = iTermTerminfoBooleanName(termType, i);
            const int value = tigetflag(keycstr);
            if (value != -1) {
                NSString *key = [NSString stringWithCString:keycstr encoding:NSUTF8StringEncoding];
                result[key] = value ? @YES : @NO;
            }
        }
        for (int i = 0; i < iTermTerminfoNumberOfNumbers(termType); i++) {
            char *keycstr = iTermTerminfoNumberName(termType, i);
            const int value = tigetnum(keycstr);
            if (value != -1) {
                NSString *key = [NSString stringWithCString:keycstr encoding:NSUTF8StringEncoding];
                result[key] = @(value);
            }
        }
        free(term);
        term = NULL;
        return result;
    }];
}

- (NSNumber *)booleanForKey:(iTermTerminfoBoolean)key {
    return [self sync:^id{
        switch (key) {
            case iTermTerminfoBoolean_auto_left_margin:
                return @(auto_left_margin);
            case iTermTerminfoBoolean_auto_right_margin:
                return @(auto_right_margin);
            case iTermTerminfoBoolean_no_esc_ctlc:
                return @(no_esc_ctlc);
            case iTermTerminfoBoolean_ceol_standout_glitch:
                return @(ceol_standout_glitch);
            case iTermTerminfoBoolean_eat_newline_glitch:
                return @(eat_newline_glitch);
            case iTermTerminfoBoolean_erase_overstrike:
                return @(erase_overstrike);
            case iTermTerminfoBoolean_generic_type:
                return @(generic_type);
            case iTermTerminfoBoolean_hard_copy:
                return @(hard_copy);
            case iTermTerminfoBoolean_has_meta_key:
                return @(has_meta_key);
            case iTermTerminfoBoolean_has_status_line:
                return @(has_status_line);
            case iTermTerminfoBoolean_insert_null_glitch:
                return @(insert_null_glitch);
            case iTermTerminfoBoolean_memory_above:
                return @(memory_above);
            case iTermTerminfoBoolean_memory_below:
                return @(memory_below);
            case iTermTerminfoBoolean_move_insert_mode:
                return @(move_insert_mode);
            case iTermTerminfoBoolean_move_standout_mode:
                return @(move_standout_mode);
            case iTermTerminfoBoolean_over_strike:
                return @(over_strike);
            case iTermTerminfoBoolean_status_line_esc_ok:
                return @(status_line_esc_ok);
            case iTermTerminfoBoolean_dest_tabs_magic_smso:
                return @(dest_tabs_magic_smso);
            case iTermTerminfoBoolean_tilde_glitch:
                return @(tilde_glitch);
            case iTermTerminfoBoolean_transparent_underline:
                return @(transparent_underline);
            case iTermTerminfoBoolean_xon_xoff:
                return @(xon_xoff);
            case iTermTerminfoBoolean_needs_xon_xoff:
                return @(needs_xon_xoff);
            case iTermTerminfoBoolean_prtr_silent:
                return @(prtr_silent);
            case iTermTerminfoBoolean_hard_cursor:
                return @(hard_cursor);
            case iTermTerminfoBoolean_non_rev_rmcup:
                return @(non_rev_rmcup);
            case iTermTerminfoBoolean_no_pad_char:
                return @(no_pad_char);
            case iTermTerminfoBoolean_non_dest_scroll_region:
                return @(non_dest_scroll_region);
            case iTermTerminfoBoolean_can_change:
                return @(can_change);
            case iTermTerminfoBoolean_back_color_erase:
                return @(back_color_erase);
            case iTermTerminfoBoolean_hue_lightness_saturation:
                return @(hue_lightness_saturation);
            case iTermTerminfoBoolean_col_addr_glitch:
                return @(col_addr_glitch);
            case iTermTerminfoBoolean_cr_cancels_micro_mode:
                return @(cr_cancels_micro_mode);
            case iTermTerminfoBoolean_has_print_wheel:
                return @(has_print_wheel);
            case iTermTerminfoBoolean_row_addr_glitch:
                return @(row_addr_glitch);
            case iTermTerminfoBoolean_semi_auto_right_margin:
                return @(semi_auto_right_margin);
            case iTermTerminfoBoolean_cpi_changes_res:
                return @(cpi_changes_res);
            case iTermTerminfoBoolean_lpi_changes_res:
                return @(lpi_changes_res);
        }
        return nil;
    }];
}

- (NSNumber *)numberForKey:(iTermTerminfoNumber)key {
    return [self sync:^id{
        switch (key) {
            case iTermTerminfoNumber_columns:
                return @(columns);
            case iTermTerminfoNumber_init_tabs:
                return @(init_tabs);
            case iTermTerminfoNumber_lines:
                return @(lines);
            case iTermTerminfoNumber_lines_of_memory:
                return @(lines_of_memory);
            case iTermTerminfoNumber_magic_cookie_glitch:
                return @(magic_cookie_glitch);
            case iTermTerminfoNumber_padding_baud_rate:
                return @(padding_baud_rate);
            case iTermTerminfoNumber_virtual_terminal:
                return @(virtual_terminal);
            case iTermTerminfoNumber_width_status_line:
                return @(width_status_line);
            case iTermTerminfoNumber_num_labels:
                return @(num_labels);
            case iTermTerminfoNumber_label_height:
                return @(label_height);
            case iTermTerminfoNumber_label_width:
                return @(label_width);
            case iTermTerminfoNumber_max_attributes:
                return @(max_attributes);
            case iTermTerminfoNumber_maximum_windows:
                return @(maximum_windows);
            case iTermTerminfoNumber_max_colors:
                return @(max_colors);
            case iTermTerminfoNumber_max_pairs:
                return @(max_pairs);
            case iTermTerminfoNumber_no_color_video:
                return @(no_color_video);
            case iTermTerminfoNumber_buffer_capacity:
                return @(buffer_capacity);
            case iTermTerminfoNumber_dot_vert_spacing:
                return @(dot_vert_spacing);
            case iTermTerminfoNumber_dot_horz_spacing:
                return @(dot_horz_spacing);
            case iTermTerminfoNumber_max_micro_address:
                return @(max_micro_address);
            case iTermTerminfoNumber_max_micro_jump:
                return @(max_micro_jump);
            case iTermTerminfoNumber_micro_col_size:
                return @(micro_col_size);
            case iTermTerminfoNumber_micro_line_size:
                return @(micro_line_size);
            case iTermTerminfoNumber_number_of_pins:
                return @(number_of_pins);
            case iTermTerminfoNumber_output_res_char:
                return @(output_res_char);
            case iTermTerminfoNumber_output_res_line:
                return @(output_res_line);
            case iTermTerminfoNumber_output_res_horz_inch:
                return @(output_res_horz_inch);
            case iTermTerminfoNumber_output_res_vert_inch:
                return @(output_res_vert_inch);
            case iTermTerminfoNumber_print_rate:
                return @(print_rate);
            case iTermTerminfoNumber_wide_char_size:
                return @(wide_char_size);
            case iTermTerminfoNumber_buttons:
                return @(buttons);
            case iTermTerminfoNumber_bit_image_entwining:
                return @(bit_image_entwining);
            case iTermTerminfoNumber_bit_image_type:
                return @(bit_image_type);
        }
        return nil;
    }];
}

- (NSString *)stringFrom:(const char *)cStr {
    if (!cStr) {
        return nil;
    }
    return [NSString stringWithCString:cStr encoding:NSUTF8StringEncoding];
}

- (NSString *)stringForKey:(iTermTerminfoString)key {
    return [self sync:^id{
        switch (key) {
            case iTermTerminfoString_back_tab:
                return [self stringFrom:back_tab];
            case iTermTerminfoString_bell:
                return [self stringFrom:bell];
            case iTermTerminfoString_carriage_return:
                return [self stringFrom:carriage_return];
            case iTermTerminfoString_change_scroll_region:
                return [self stringFrom:change_scroll_region];
            case iTermTerminfoString_clear_all_tabs:
                return [self stringFrom:clear_all_tabs];
            case iTermTerminfoString_clear_screen:
                return [self stringFrom:clear_screen];
            case iTermTerminfoString_clr_eol:
                return [self stringFrom:clr_eol];
            case iTermTerminfoString_clr_eos:
                return [self stringFrom:clr_eos];
            case iTermTerminfoString_column_address:
                return [self stringFrom:column_address];
            case iTermTerminfoString_command_character:
                return [self stringFrom:command_character];
            case iTermTerminfoString_cursor_address:
                return [self stringFrom:cursor_address];
            case iTermTerminfoString_cursor_down:
                return [self stringFrom:cursor_down];
            case iTermTerminfoString_cursor_home:
                return [self stringFrom:cursor_home];
            case iTermTerminfoString_cursor_invisible:
                return [self stringFrom:cursor_invisible];
            case iTermTerminfoString_cursor_left:
                return [self stringFrom:cursor_left];
            case iTermTerminfoString_cursor_mem_address:
                return [self stringFrom:cursor_mem_address];
            case iTermTerminfoString_cursor_normal:
                return [self stringFrom:cursor_normal];
            case iTermTerminfoString_cursor_right:
                return [self stringFrom:cursor_right];
            case iTermTerminfoString_cursor_to_ll:
                return [self stringFrom:cursor_to_ll];
            case iTermTerminfoString_cursor_up:
                return [self stringFrom:cursor_up];
            case iTermTerminfoString_cursor_visible:
                return [self stringFrom:cursor_visible];
            case iTermTerminfoString_delete_character:
                return [self stringFrom:delete_character];
            case iTermTerminfoString_delete_line:
                return [self stringFrom:delete_line];
            case iTermTerminfoString_dis_status_line:
                return [self stringFrom:dis_status_line];
            case iTermTerminfoString_down_half_line:
                return [self stringFrom:down_half_line];
            case iTermTerminfoString_enter_alt_charset_mode:
                return [self stringFrom:enter_alt_charset_mode];
            case iTermTerminfoString_enter_blink_mode:
                return [self stringFrom:enter_blink_mode];
            case iTermTerminfoString_enter_bold_mode:
                return [self stringFrom:enter_bold_mode];
            case iTermTerminfoString_enter_ca_mode:
                return [self stringFrom:enter_ca_mode];
            case iTermTerminfoString_enter_delete_mode:
                return [self stringFrom:enter_delete_mode];
            case iTermTerminfoString_enter_dim_mode:
                return [self stringFrom:enter_dim_mode];
            case iTermTerminfoString_enter_insert_mode:
                return [self stringFrom:enter_insert_mode];
            case iTermTerminfoString_enter_secure_mode:
                return [self stringFrom:enter_secure_mode];
            case iTermTerminfoString_enter_protected_mode:
                return [self stringFrom:enter_protected_mode];
            case iTermTerminfoString_enter_reverse_mode:
                return [self stringFrom:enter_reverse_mode];
            case iTermTerminfoString_enter_standout_mode:
                return [self stringFrom:enter_standout_mode];
            case iTermTerminfoString_enter_underline_mode:
                return [self stringFrom:enter_underline_mode];
            case iTermTerminfoString_erase_chars:
                return [self stringFrom:erase_chars];
            case iTermTerminfoString_exit_alt_charset_mode:
                return [self stringFrom:exit_alt_charset_mode];
            case iTermTerminfoString_exit_attribute_mode:
                return [self stringFrom:exit_attribute_mode];
            case iTermTerminfoString_exit_ca_mode:
                return [self stringFrom:exit_ca_mode];
            case iTermTerminfoString_exit_delete_mode:
                return [self stringFrom:exit_delete_mode];
            case iTermTerminfoString_exit_insert_mode:
                return [self stringFrom:exit_insert_mode];
            case iTermTerminfoString_exit_standout_mode:
                return [self stringFrom:exit_standout_mode];
            case iTermTerminfoString_exit_underline_mode:
                return [self stringFrom:exit_underline_mode];
            case iTermTerminfoString_flash_screen:
                return [self stringFrom:flash_screen];
            case iTermTerminfoString_form_feed:
                return [self stringFrom:form_feed];
            case iTermTerminfoString_from_status_line:
                return [self stringFrom:from_status_line];
            case iTermTerminfoString_init_1string:
                return [self stringFrom:init_1string];
            case iTermTerminfoString_init_2string:
                return [self stringFrom:init_2string];
            case iTermTerminfoString_init_3string:
                return [self stringFrom:init_3string];
            case iTermTerminfoString_init_file:
                return [self stringFrom:init_file];
            case iTermTerminfoString_insert_character:
                return [self stringFrom:insert_character];
            case iTermTerminfoString_insert_line:
                return [self stringFrom:insert_line];
            case iTermTerminfoString_insert_padding:
                return [self stringFrom:insert_padding];
            case iTermTerminfoString_key_backspace:
                return [self stringFrom:key_backspace];
            case iTermTerminfoString_key_catab:
                return [self stringFrom:key_catab];
            case iTermTerminfoString_key_clear:
                return [self stringFrom:key_clear];
            case iTermTerminfoString_key_ctab:
                return [self stringFrom:key_ctab];
            case iTermTerminfoString_key_dc:
                return [self stringFrom:key_dc];
            case iTermTerminfoString_key_dl:
                return [self stringFrom:key_dl];
            case iTermTerminfoString_key_down:
                return [self stringFrom:key_down];
            case iTermTerminfoString_key_eic:
                return [self stringFrom:key_eic];
            case iTermTerminfoString_key_eol:
                return [self stringFrom:key_eol];
            case iTermTerminfoString_key_eos:
                return [self stringFrom:key_eos];
            case iTermTerminfoString_key_f0:
                return [self stringFrom:key_f0];
            case iTermTerminfoString_key_f1:
                return [self stringFrom:key_f1];
            case iTermTerminfoString_key_f10:
                return [self stringFrom:key_f10];
            case iTermTerminfoString_key_f2:
                return [self stringFrom:key_f2];
            case iTermTerminfoString_key_f3:
                return [self stringFrom:key_f3];
            case iTermTerminfoString_key_f4:
                return [self stringFrom:key_f4];
            case iTermTerminfoString_key_f5:
                return [self stringFrom:key_f5];
            case iTermTerminfoString_key_f6:
                return [self stringFrom:key_f6];
            case iTermTerminfoString_key_f7:
                return [self stringFrom:key_f7];
            case iTermTerminfoString_key_f8:
                return [self stringFrom:key_f8];
            case iTermTerminfoString_key_f9:
                return [self stringFrom:key_f9];
            case iTermTerminfoString_key_home:
                return [self stringFrom:key_home];
            case iTermTerminfoString_key_ic:
                return [self stringFrom:key_ic];
            case iTermTerminfoString_key_il:
                return [self stringFrom:key_il];
            case iTermTerminfoString_key_left:
                return [self stringFrom:key_left];
            case iTermTerminfoString_key_ll:
                return [self stringFrom:key_ll];
            case iTermTerminfoString_key_npage:
                return [self stringFrom:key_npage];
            case iTermTerminfoString_key_ppage:
                return [self stringFrom:key_ppage];
            case iTermTerminfoString_key_right:
                return [self stringFrom:key_right];
            case iTermTerminfoString_key_sf:
                return [self stringFrom:key_sf];
            case iTermTerminfoString_key_sr:
                return [self stringFrom:key_sr];
            case iTermTerminfoString_key_stab:
                return [self stringFrom:key_stab];
            case iTermTerminfoString_key_up:
                return [self stringFrom:key_up];
            case iTermTerminfoString_keypad_local:
                return [self stringFrom:keypad_local];
            case iTermTerminfoString_keypad_xmit:
                return [self stringFrom:keypad_xmit];
            case iTermTerminfoString_lab_f0:
                return [self stringFrom:lab_f0];
            case iTermTerminfoString_lab_f1:
                return [self stringFrom:lab_f1];
            case iTermTerminfoString_lab_f10:
                return [self stringFrom:lab_f10];
            case iTermTerminfoString_lab_f2:
                return [self stringFrom:lab_f2];
            case iTermTerminfoString_lab_f3:
                return [self stringFrom:lab_f3];
            case iTermTerminfoString_lab_f4:
                return [self stringFrom:lab_f4];
            case iTermTerminfoString_lab_f5:
                return [self stringFrom:lab_f5];
            case iTermTerminfoString_lab_f6:
                return [self stringFrom:lab_f6];
            case iTermTerminfoString_lab_f7:
                return [self stringFrom:lab_f7];
            case iTermTerminfoString_lab_f8:
                return [self stringFrom:lab_f8];
            case iTermTerminfoString_lab_f9:
                return [self stringFrom:lab_f9];
            case iTermTerminfoString_meta_off:
                return [self stringFrom:meta_off];
            case iTermTerminfoString_meta_on:
                return [self stringFrom:meta_on];
            case iTermTerminfoString_newline:
                return [self stringFrom:newline];
            case iTermTerminfoString_pad_char:
                return [self stringFrom:pad_char];
            case iTermTerminfoString_parm_dch:
                return [self stringFrom:parm_dch];
            case iTermTerminfoString_parm_delete_line:
                return [self stringFrom:parm_delete_line];
            case iTermTerminfoString_parm_down_cursor:
                return [self stringFrom:parm_down_cursor];
            case iTermTerminfoString_parm_ich:
                return [self stringFrom:parm_ich];
            case iTermTerminfoString_parm_index:
                return [self stringFrom:parm_index];
            case iTermTerminfoString_parm_insert_line:
                return [self stringFrom:parm_insert_line];
            case iTermTerminfoString_parm_left_cursor:
                return [self stringFrom:parm_left_cursor];
            case iTermTerminfoString_parm_right_cursor:
                return [self stringFrom:parm_right_cursor];
            case iTermTerminfoString_parm_rindex:
                return [self stringFrom:parm_rindex];
            case iTermTerminfoString_parm_up_cursor:
                return [self stringFrom:parm_up_cursor];
            case iTermTerminfoString_pkey_key:
                return [self stringFrom:pkey_key];
            case iTermTerminfoString_pkey_local:
                return [self stringFrom:pkey_local];
            case iTermTerminfoString_pkey_xmit:
                return [self stringFrom:pkey_xmit];
            case iTermTerminfoString_print_screen:
                return [self stringFrom:print_screen];
            case iTermTerminfoString_prtr_off:
                return [self stringFrom:prtr_off];
            case iTermTerminfoString_prtr_on:
                return [self stringFrom:prtr_on];
            case iTermTerminfoString_repeat_char:
                return [self stringFrom:repeat_char];
            case iTermTerminfoString_reset_1string:
                return [self stringFrom:reset_1string];
            case iTermTerminfoString_reset_2string:
                return [self stringFrom:reset_2string];
            case iTermTerminfoString_reset_3string:
                return [self stringFrom:reset_3string];
            case iTermTerminfoString_reset_file:
                return [self stringFrom:reset_file];
            case iTermTerminfoString_restore_cursor:
                return [self stringFrom:restore_cursor];
            case iTermTerminfoString_row_address:
                return [self stringFrom:row_address];
            case iTermTerminfoString_save_cursor:
                return [self stringFrom:save_cursor];
            case iTermTerminfoString_scroll_forward:
                return [self stringFrom:scroll_forward];
            case iTermTerminfoString_scroll_reverse:
                return [self stringFrom:scroll_reverse];
            case iTermTerminfoString_set_attributes:
                return [self stringFrom:set_attributes];
            case iTermTerminfoString_set_tab:
                return [self stringFrom:set_tab];
            case iTermTerminfoString_set_window:
                return [self stringFrom:set_window];
            case iTermTerminfoString_tab:
                return [self stringFrom:tab];
            case iTermTerminfoString_to_status_line:
                return [self stringFrom:to_status_line];
            case iTermTerminfoString_underline_char:
                return [self stringFrom:underline_char];
            case iTermTerminfoString_up_half_line:
                return [self stringFrom:up_half_line];
            case iTermTerminfoString_init_prog:
                return [self stringFrom:init_prog];
            case iTermTerminfoString_key_a1:
                return [self stringFrom:key_a1];
            case iTermTerminfoString_key_a3:
                return [self stringFrom:key_a3];
            case iTermTerminfoString_key_b2:
                return [self stringFrom:key_b2];
            case iTermTerminfoString_key_c1:
                return [self stringFrom:key_c1];
            case iTermTerminfoString_key_c3:
                return [self stringFrom:key_c3];
            case iTermTerminfoString_prtr_non:
                return [self stringFrom:prtr_non];
            case iTermTerminfoString_char_padding:
                return [self stringFrom:char_padding];
            case iTermTerminfoString_acs_chars:
                return [self stringFrom:acs_chars];
            case iTermTerminfoString_plab_norm:
                return [self stringFrom:plab_norm];
            case iTermTerminfoString_key_btab:
                return [self stringFrom:key_btab];
            case iTermTerminfoString_enter_xon_mode:
                return [self stringFrom:enter_xon_mode];
            case iTermTerminfoString_exit_xon_mode:
                return [self stringFrom:exit_xon_mode];
            case iTermTerminfoString_enter_am_mode:
                return [self stringFrom:enter_am_mode];
            case iTermTerminfoString_exit_am_mode:
                return [self stringFrom:exit_am_mode];
            case iTermTerminfoString_xon_character:
                return [self stringFrom:xon_character];
            case iTermTerminfoString_xoff_character:
                return [self stringFrom:xoff_character];
            case iTermTerminfoString_ena_acs:
                return [self stringFrom:ena_acs];
            case iTermTerminfoString_label_on:
                return [self stringFrom:label_on];
            case iTermTerminfoString_label_off:
                return [self stringFrom:label_off];
            case iTermTerminfoString_key_beg:
                return [self stringFrom:key_beg];
            case iTermTerminfoString_key_cancel:
                return [self stringFrom:key_cancel];
            case iTermTerminfoString_key_close:
                return [self stringFrom:key_close];
            case iTermTerminfoString_key_command:
                return [self stringFrom:key_command];
            case iTermTerminfoString_key_copy:
                return [self stringFrom:key_copy];
            case iTermTerminfoString_key_create:
                return [self stringFrom:key_create];
            case iTermTerminfoString_key_end:
                return [self stringFrom:key_end];
            case iTermTerminfoString_key_enter:
                return [self stringFrom:key_enter];
            case iTermTerminfoString_key_exit:
                return [self stringFrom:key_exit];
            case iTermTerminfoString_key_find:
                return [self stringFrom:key_find];
            case iTermTerminfoString_key_help:
                return [self stringFrom:key_help];
            case iTermTerminfoString_key_mark:
                return [self stringFrom:key_mark];
            case iTermTerminfoString_key_message:
                return [self stringFrom:key_message];
            case iTermTerminfoString_key_move:
                return [self stringFrom:key_move];
            case iTermTerminfoString_key_next:
                return [self stringFrom:key_next];
            case iTermTerminfoString_key_open:
                return [self stringFrom:key_open];
            case iTermTerminfoString_key_options:
                return [self stringFrom:key_options];
            case iTermTerminfoString_key_previous:
                return [self stringFrom:key_previous];
            case iTermTerminfoString_key_print:
                return [self stringFrom:key_print];
            case iTermTerminfoString_key_redo:
                return [self stringFrom:key_redo];
            case iTermTerminfoString_key_reference:
                return [self stringFrom:key_reference];
            case iTermTerminfoString_key_refresh:
                return [self stringFrom:key_refresh];
            case iTermTerminfoString_key_replace:
                return [self stringFrom:key_replace];
            case iTermTerminfoString_key_restart:
                return [self stringFrom:key_restart];
            case iTermTerminfoString_key_resume:
                return [self stringFrom:key_resume];
            case iTermTerminfoString_key_save:
                return [self stringFrom:key_save];
            case iTermTerminfoString_key_suspend:
                return [self stringFrom:key_suspend];
            case iTermTerminfoString_key_undo:
                return [self stringFrom:key_undo];
            case iTermTerminfoString_key_sbeg:
                return [self stringFrom:key_sbeg];
            case iTermTerminfoString_key_scancel:
                return [self stringFrom:key_scancel];
            case iTermTerminfoString_key_scommand:
                return [self stringFrom:key_scommand];
            case iTermTerminfoString_key_scopy:
                return [self stringFrom:key_scopy];
            case iTermTerminfoString_key_screate:
                return [self stringFrom:key_screate];
            case iTermTerminfoString_key_sdc:
                return [self stringFrom:key_sdc];
            case iTermTerminfoString_key_sdl:
                return [self stringFrom:key_sdl];
            case iTermTerminfoString_key_select:
                return [self stringFrom:key_select];
            case iTermTerminfoString_key_send:
                return [self stringFrom:key_send];
            case iTermTerminfoString_key_seol:
                return [self stringFrom:key_seol];
            case iTermTerminfoString_key_sexit:
                return [self stringFrom:key_sexit];
            case iTermTerminfoString_key_sfind:
                return [self stringFrom:key_sfind];
            case iTermTerminfoString_key_shelp:
                return [self stringFrom:key_shelp];
            case iTermTerminfoString_key_shome:
                return [self stringFrom:key_shome];
            case iTermTerminfoString_key_sic:
                return [self stringFrom:key_sic];
            case iTermTerminfoString_key_sleft:
                return [self stringFrom:key_sleft];
            case iTermTerminfoString_key_smessage:
                return [self stringFrom:key_smessage];
            case iTermTerminfoString_key_smove:
                return [self stringFrom:key_smove];
            case iTermTerminfoString_key_snext:
                return [self stringFrom:key_snext];
            case iTermTerminfoString_key_soptions:
                return [self stringFrom:key_soptions];
            case iTermTerminfoString_key_sprevious:
                return [self stringFrom:key_sprevious];
            case iTermTerminfoString_key_sprint:
                return [self stringFrom:key_sprint];
            case iTermTerminfoString_key_sredo:
                return [self stringFrom:key_sredo];
            case iTermTerminfoString_key_sreplace:
                return [self stringFrom:key_sreplace];
            case iTermTerminfoString_key_sright:
                return [self stringFrom:key_sright];
            case iTermTerminfoString_key_srsume:
                return [self stringFrom:key_srsume];
            case iTermTerminfoString_key_ssave:
                return [self stringFrom:key_ssave];
            case iTermTerminfoString_key_ssuspend:
                return [self stringFrom:key_ssuspend];
            case iTermTerminfoString_key_sundo:
                return [self stringFrom:key_sundo];
            case iTermTerminfoString_req_for_input:
                return [self stringFrom:req_for_input];
            case iTermTerminfoString_key_f11:
                return [self stringFrom:key_f11];
            case iTermTerminfoString_key_f12:
                return [self stringFrom:key_f12];
            case iTermTerminfoString_key_f13:
                return [self stringFrom:key_f13];
            case iTermTerminfoString_key_f14:
                return [self stringFrom:key_f14];
            case iTermTerminfoString_key_f15:
                return [self stringFrom:key_f15];
            case iTermTerminfoString_key_f16:
                return [self stringFrom:key_f16];
            case iTermTerminfoString_key_f17:
                return [self stringFrom:key_f17];
            case iTermTerminfoString_key_f18:
                return [self stringFrom:key_f18];
            case iTermTerminfoString_key_f19:
                return [self stringFrom:key_f19];
            case iTermTerminfoString_key_f20:
                return [self stringFrom:key_f20];
            case iTermTerminfoString_key_f21:
                return [self stringFrom:key_f21];
            case iTermTerminfoString_key_f22:
                return [self stringFrom:key_f22];
            case iTermTerminfoString_key_f23:
                return [self stringFrom:key_f23];
            case iTermTerminfoString_key_f24:
                return [self stringFrom:key_f24];
            case iTermTerminfoString_key_f25:
                return [self stringFrom:key_f25];
            case iTermTerminfoString_key_f26:
                return [self stringFrom:key_f26];
            case iTermTerminfoString_key_f27:
                return [self stringFrom:key_f27];
            case iTermTerminfoString_key_f28:
                return [self stringFrom:key_f28];
            case iTermTerminfoString_key_f29:
                return [self stringFrom:key_f29];
            case iTermTerminfoString_key_f30:
                return [self stringFrom:key_f30];
            case iTermTerminfoString_key_f31:
                return [self stringFrom:key_f31];
            case iTermTerminfoString_key_f32:
                return [self stringFrom:key_f32];
            case iTermTerminfoString_key_f33:
                return [self stringFrom:key_f33];
            case iTermTerminfoString_key_f34:
                return [self stringFrom:key_f34];
            case iTermTerminfoString_key_f35:
                return [self stringFrom:key_f35];
            case iTermTerminfoString_key_f36:
                return [self stringFrom:key_f36];
            case iTermTerminfoString_key_f37:
                return [self stringFrom:key_f37];
            case iTermTerminfoString_key_f38:
                return [self stringFrom:key_f38];
            case iTermTerminfoString_key_f39:
                return [self stringFrom:key_f39];
            case iTermTerminfoString_key_f40:
                return [self stringFrom:key_f40];
            case iTermTerminfoString_key_f41:
                return [self stringFrom:key_f41];
            case iTermTerminfoString_key_f42:
                return [self stringFrom:key_f42];
            case iTermTerminfoString_key_f43:
                return [self stringFrom:key_f43];
            case iTermTerminfoString_key_f44:
                return [self stringFrom:key_f44];
            case iTermTerminfoString_key_f45:
                return [self stringFrom:key_f45];
            case iTermTerminfoString_key_f46:
                return [self stringFrom:key_f46];
            case iTermTerminfoString_key_f47:
                return [self stringFrom:key_f47];
            case iTermTerminfoString_key_f48:
                return [self stringFrom:key_f48];
            case iTermTerminfoString_key_f49:
                return [self stringFrom:key_f49];
            case iTermTerminfoString_key_f50:
                return [self stringFrom:key_f50];
            case iTermTerminfoString_key_f51:
                return [self stringFrom:key_f51];
            case iTermTerminfoString_key_f52:
                return [self stringFrom:key_f52];
            case iTermTerminfoString_key_f53:
                return [self stringFrom:key_f53];
            case iTermTerminfoString_key_f54:
                return [self stringFrom:key_f54];
            case iTermTerminfoString_key_f55:
                return [self stringFrom:key_f55];
            case iTermTerminfoString_key_f56:
                return [self stringFrom:key_f56];
            case iTermTerminfoString_key_f57:
                return [self stringFrom:key_f57];
            case iTermTerminfoString_key_f58:
                return [self stringFrom:key_f58];
            case iTermTerminfoString_key_f59:
                return [self stringFrom:key_f59];
            case iTermTerminfoString_key_f60:
                return [self stringFrom:key_f60];
            case iTermTerminfoString_key_f61:
                return [self stringFrom:key_f61];
            case iTermTerminfoString_key_f62:
                return [self stringFrom:key_f62];
            case iTermTerminfoString_key_f63:
                return [self stringFrom:key_f63];
            case iTermTerminfoString_clr_bol:
                return [self stringFrom:clr_bol];
            case iTermTerminfoString_clear_margins:
                return [self stringFrom:clear_margins];
            case iTermTerminfoString_set_left_margin:
                return [self stringFrom:set_left_margin];
            case iTermTerminfoString_set_right_margin:
                return [self stringFrom:set_right_margin];
            case iTermTerminfoString_label_format:
                return [self stringFrom:label_format];
            case iTermTerminfoString_set_clock:
                return [self stringFrom:set_clock];
            case iTermTerminfoString_display_clock:
                return [self stringFrom:display_clock];
            case iTermTerminfoString_remove_clock:
                return [self stringFrom:remove_clock];
            case iTermTerminfoString_create_window:
                return [self stringFrom:create_window];
            case iTermTerminfoString_goto_window:
                return [self stringFrom:goto_window];
            case iTermTerminfoString_hangup:
                return [self stringFrom:hangup];
            case iTermTerminfoString_dial_phone:
                return [self stringFrom:dial_phone];
            case iTermTerminfoString_quick_dial:
                return [self stringFrom:quick_dial];
            case iTermTerminfoString_tone:
                return [self stringFrom:tone];
            case iTermTerminfoString_pulse:
                return [self stringFrom:pulse];
            case iTermTerminfoString_flash_hook:
                return [self stringFrom:flash_hook];
            case iTermTerminfoString_fixed_pause:
                return [self stringFrom:fixed_pause];
            case iTermTerminfoString_wait_tone:
                return [self stringFrom:wait_tone];
            case iTermTerminfoString_user0:
                return [self stringFrom:user0];
            case iTermTerminfoString_user1:
                return [self stringFrom:user1];
            case iTermTerminfoString_user2:
                return [self stringFrom:user2];
            case iTermTerminfoString_user3:
                return [self stringFrom:user3];
            case iTermTerminfoString_user4:
                return [self stringFrom:user4];
            case iTermTerminfoString_user5:
                return [self stringFrom:user5];
            case iTermTerminfoString_user6:
                return [self stringFrom:user6];
            case iTermTerminfoString_user7:
                return [self stringFrom:user7];
            case iTermTerminfoString_user8:
                return [self stringFrom:user8];
            case iTermTerminfoString_user9:
                return [self stringFrom:user9];
            case iTermTerminfoString_orig_pair:
                return [self stringFrom:orig_pair];
            case iTermTerminfoString_orig_colors:
                return [self stringFrom:orig_colors];
            case iTermTerminfoString_initialize_color:
                return [self stringFrom:initialize_color];
            case iTermTerminfoString_initialize_pair:
                return [self stringFrom:initialize_pair];
            case iTermTerminfoString_set_color_pair:
                return [self stringFrom:set_color_pair];
            case iTermTerminfoString_set_foreground:
                return [self stringFrom:set_foreground];
            case iTermTerminfoString_set_background:
                return [self stringFrom:set_background];
            case iTermTerminfoString_change_char_pitch:
                return [self stringFrom:change_char_pitch];
            case iTermTerminfoString_change_line_pitch:
                return [self stringFrom:change_line_pitch];
            case iTermTerminfoString_change_res_horz:
                return [self stringFrom:change_res_horz];
            case iTermTerminfoString_change_res_vert:
                return [self stringFrom:change_res_vert];
            case iTermTerminfoString_define_char:
                return [self stringFrom:define_char];
            case iTermTerminfoString_enter_doublewide_mode:
                return [self stringFrom:enter_doublewide_mode];
            case iTermTerminfoString_enter_draft_quality:
                return [self stringFrom:enter_draft_quality];
            case iTermTerminfoString_enter_italics_mode:
                return [self stringFrom:enter_italics_mode];
            case iTermTerminfoString_enter_leftward_mode:
                return [self stringFrom:enter_leftward_mode];
            case iTermTerminfoString_enter_micro_mode:
                return [self stringFrom:enter_micro_mode];
            case iTermTerminfoString_enter_near_letter_quality:
                return [self stringFrom:enter_near_letter_quality];
            case iTermTerminfoString_enter_normal_quality:
                return [self stringFrom:enter_normal_quality];
            case iTermTerminfoString_enter_shadow_mode:
                return [self stringFrom:enter_shadow_mode];
            case iTermTerminfoString_enter_subscript_mode:
                return [self stringFrom:enter_subscript_mode];
            case iTermTerminfoString_enter_superscript_mode:
                return [self stringFrom:enter_superscript_mode];
            case iTermTerminfoString_enter_upward_mode:
                return [self stringFrom:enter_upward_mode];
            case iTermTerminfoString_exit_doublewide_mode:
                return [self stringFrom:exit_doublewide_mode];
            case iTermTerminfoString_exit_italics_mode:
                return [self stringFrom:exit_italics_mode];
            case iTermTerminfoString_exit_leftward_mode:
                return [self stringFrom:exit_leftward_mode];
            case iTermTerminfoString_exit_micro_mode:
                return [self stringFrom:exit_micro_mode];
            case iTermTerminfoString_exit_shadow_mode:
                return [self stringFrom:exit_shadow_mode];
            case iTermTerminfoString_exit_subscript_mode:
                return [self stringFrom:exit_subscript_mode];
            case iTermTerminfoString_exit_superscript_mode:
                return [self stringFrom:exit_superscript_mode];
            case iTermTerminfoString_exit_upward_mode:
                return [self stringFrom:exit_upward_mode];
            case iTermTerminfoString_micro_column_address:
                return [self stringFrom:micro_column_address];
            case iTermTerminfoString_micro_down:
                return [self stringFrom:micro_down];
            case iTermTerminfoString_micro_left:
                return [self stringFrom:micro_left];
            case iTermTerminfoString_micro_right:
                return [self stringFrom:micro_right];
            case iTermTerminfoString_micro_row_address:
                return [self stringFrom:micro_row_address];
            case iTermTerminfoString_micro_up:
                return [self stringFrom:micro_up];
            case iTermTerminfoString_order_of_pins:
                return [self stringFrom:order_of_pins];
            case iTermTerminfoString_parm_down_micro:
                return [self stringFrom:parm_down_micro];
            case iTermTerminfoString_parm_left_micro:
                return [self stringFrom:parm_left_micro];
            case iTermTerminfoString_parm_right_micro:
                return [self stringFrom:parm_right_micro];
            case iTermTerminfoString_parm_up_micro:
                return [self stringFrom:parm_up_micro];
            case iTermTerminfoString_select_char_set:
                return [self stringFrom:select_char_set];
            case iTermTerminfoString_set_bottom_margin:
                return [self stringFrom:set_bottom_margin];
            case iTermTerminfoString_set_bottom_margin_parm:
                return [self stringFrom:set_bottom_margin_parm];
            case iTermTerminfoString_set_left_margin_parm:
                return [self stringFrom:set_left_margin_parm];
            case iTermTerminfoString_set_right_margin_parm:
                return [self stringFrom:set_right_margin_parm];
            case iTermTerminfoString_set_top_margin:
                return [self stringFrom:set_top_margin];
            case iTermTerminfoString_set_top_margin_parm:
                return [self stringFrom:set_top_margin_parm];
            case iTermTerminfoString_start_bit_image:
                return [self stringFrom:start_bit_image];
            case iTermTerminfoString_start_char_set_def:
                return [self stringFrom:start_char_set_def];
            case iTermTerminfoString_stop_bit_image:
                return [self stringFrom:stop_bit_image];
            case iTermTerminfoString_stop_char_set_def:
                return [self stringFrom:stop_char_set_def];
            case iTermTerminfoString_subscript_characters:
                return [self stringFrom:subscript_characters];
            case iTermTerminfoString_superscript_characters:
                return [self stringFrom:superscript_characters];
            case iTermTerminfoString_these_cause_cr:
                return [self stringFrom:these_cause_cr];
            case iTermTerminfoString_zero_motion:
                return [self stringFrom:zero_motion];
            case iTermTerminfoString_char_set_names:
                return [self stringFrom:char_set_names];
            case iTermTerminfoString_key_mouse:
                return [self stringFrom:key_mouse];
            case iTermTerminfoString_mouse_info:
                return [self stringFrom:mouse_info];
            case iTermTerminfoString_req_mouse_pos:
                return [self stringFrom:req_mouse_pos];
            case iTermTerminfoString_get_mouse:
                return [self stringFrom:get_mouse];
            case iTermTerminfoString_set_a_foreground:
                return [self stringFrom:set_a_foreground];
            case iTermTerminfoString_set_a_background:
                return [self stringFrom:set_a_background];
            case iTermTerminfoString_pkey_plab:
                return [self stringFrom:pkey_plab];
            case iTermTerminfoString_device_type:
                return [self stringFrom:device_type];
            case iTermTerminfoString_code_set_init:
                return [self stringFrom:code_set_init];
            case iTermTerminfoString_set0_des_seq:
                return [self stringFrom:set0_des_seq];
            case iTermTerminfoString_set1_des_seq:
                return [self stringFrom:set1_des_seq];
            case iTermTerminfoString_set2_des_seq:
                return [self stringFrom:set2_des_seq];
            case iTermTerminfoString_set3_des_seq:
                return [self stringFrom:set3_des_seq];
            case iTermTerminfoString_set_lr_margin:
                return [self stringFrom:set_lr_margin];
            case iTermTerminfoString_set_tb_margin:
                return [self stringFrom:set_tb_margin];
            case iTermTerminfoString_bit_image_repeat:
                return [self stringFrom:bit_image_repeat];
            case iTermTerminfoString_bit_image_newline:
                return [self stringFrom:bit_image_newline];
            case iTermTerminfoString_bit_image_carriage_return:
                return [self stringFrom:bit_image_carriage_return];
            case iTermTerminfoString_color_names:
                return [self stringFrom:color_names];
            case iTermTerminfoString_define_bit_image_region:
                return [self stringFrom:define_bit_image_region];
            case iTermTerminfoString_end_bit_image_region:
                return [self stringFrom:end_bit_image_region];
            case iTermTerminfoString_set_color_band:
                return [self stringFrom:set_color_band];
            case iTermTerminfoString_set_page_length:
                return [self stringFrom:set_page_length];
            case iTermTerminfoString_display_pc_char:
                return [self stringFrom:display_pc_char];
            case iTermTerminfoString_enter_pc_charset_mode:
                return [self stringFrom:enter_pc_charset_mode];
            case iTermTerminfoString_exit_pc_charset_mode:
                return [self stringFrom:exit_pc_charset_mode];
            case iTermTerminfoString_enter_scancode_mode:
                return [self stringFrom:enter_scancode_mode];
            case iTermTerminfoString_exit_scancode_mode:
                return [self stringFrom:exit_scancode_mode];
            case iTermTerminfoString_pc_term_options:
                return [self stringFrom:pc_term_options];
            case iTermTerminfoString_scancode_escape:
                return [self stringFrom:scancode_escape];
            case iTermTerminfoString_alt_scancode_esc:
                return [self stringFrom:alt_scancode_esc];
            case iTermTerminfoString_enter_horizontal_hl_mode:
                return [self stringFrom:enter_horizontal_hl_mode];
            case iTermTerminfoString_enter_left_hl_mode:
                return [self stringFrom:enter_left_hl_mode];
            case iTermTerminfoString_enter_low_hl_mode:
                return [self stringFrom:enter_low_hl_mode];
            case iTermTerminfoString_enter_right_hl_mode:
                return [self stringFrom:enter_right_hl_mode];
            case iTermTerminfoString_enter_top_hl_mode:
                return [self stringFrom:enter_top_hl_mode];
            case iTermTerminfoString_enter_vertical_hl_mode:
                return [self stringFrom:enter_vertical_hl_mode];
            case iTermTerminfoString_set_a_attributes:
                return [self stringFrom:set_a_attributes];
            case iTermTerminfoString_set_pglen_inch:
                return [self stringFrom:set_pglen_inch];
        }
        return nil;
    }];
}

- (id _Nullable)objectForStringKey:(NSString *)key {
    return _database[key];
}

- (NSString * _Nullable)stringForStringKey:(NSString *)key {
    id obj = [self objectForStringKey:key];
    if (!obj) {
        return nil;
    }
    if ([obj isKindOfClass:[NSString class]]) {
        return obj;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [obj stringValue];
    }
    assert(NO);
    return nil;
}

@end
