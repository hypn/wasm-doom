// Emacs style mode select   -*- C++ -*-
//-----------------------------------------------------------------------------
//
// $Id: d6963d86b3911ed752d173bb73d28c275f4a42c7 $
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
//	Stacktrace for more useful error messages
//
//-----------------------------------------------------------------------------

#include "odamex.h"

#include "m_stacktrace.h"


std::string M_GetStacktrace(std::string header)
{
	return header + "\n\n(stack traces are not available in this build)";
}
