/*
VIRTUAL_KEYBOARD.H

header included in hcex build.
*/

#ifndef __VIRTUAL_KEYBOARD_H
#define __VIRTUAL_KEYBOARD_H
#pragma once

/* ---------- headers */

#include "cseries/cseries.h"

/* ---------- constants */

/* ---------- macros */

/* ---------- structures */

/* ---------- prototypes/EXAMPLE.C */

boolean virtual_keyboard_initialize(
	void);
void virtual_keyboard_dispose(
	void);
boolean virtual_keyboard_launch(
	wchar_t *text_buffer,
	word buffer_size,
	short caption_index);
boolean virtual_keyboard_active(
	void);
void virtual_keyboard_close(
	void);
boolean virtual_keyboard_last_exit_saved_text(
	void);
void virtual_keyboard_process(
	void);
void virtual_keyboard_render(
	void);
#ifdef HALO_LINUX
/* what the menu pointer did this frame, in the menus' 640x480 (ui_widget.c) */
void virtual_keyboard_pointer(
	short x,
	short y,
	boolean moved,
	short click_x,
	short click_y,
	long left_clicks,
	long right_clicks);
#endif

/* ---------- globals */

/* ---------- public code */

#endif // __VIRTUAL_KEYBOARD_H
