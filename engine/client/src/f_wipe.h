// Emacs style mode select   -*- C++ -*-
//-----------------------------------------------------------------------------
//
// $Id: 52d489d0bcc70a954a12d401c82c7568d6fa13b3 $
//
// Copyright (C) 1993-1996 by id Software, Inc.
// Copyright (C) 2006-2026 by The Odamex Team.
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// DESCRIPTION:
//	Mission start screen wipe/melt, special effects.
//
//-----------------------------------------------------------------------------


#pragma once

//
//						 SCREEN WIPE PACKAGE
//

void Wipe_Stop();
void Wipe_Start();
bool Wipe_Ticker();
void Wipe_Drawer();

extern int NoWipe;
