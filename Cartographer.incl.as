﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-Cartographer

import com.Utils.Archive;

import efd.Cartographer.Cartographer;

var efdCartographer:Cartographer;
// Function trigger descriptions are based upon the following settings in Modules.xml
// flags = "GMF_DONT_UNLOAD" // Don't unload/reload the entire mod every time it's disabled
// criteria contains "GUIMODEFLAGS_INPLAY | GUIMODEFLAGS_ENABLEALLGUI" // Enable only if the player is in play, or all gui is requested regardless

// Called when the clip is first loaded
// - When the player logs in a character, including on relogs
// - When /relaodui is called
// - If the mod activation distributed value is false, it may skip loading entirely
function onLoad():Void { efdCartographer = new Cartographer(this); }

// Often called in pairs, deactivating and reactivating the mod as the criteria evaluation changes
// Due to the frequency of this occuring, these should be relatively light functions
// Activate is called once immediately after onLoad
// Paired calls are made when: Changing zones, cutscenes play, the player anima leaps or is otherwise teleported
// Deactivate is called once immediately prior to OnUnload
// Toggling the distributed value will force toggle these
function OnModuleActivated(archive:Archive):Void { efdCartographer.GameToggleModEnabled(true, archive); }

function OnModuleDeactivated():Archive { return efdCartographer.GameToggleModEnabled(false); }

// Called just before the game unloads the clip
// - When the user logs out, or returns to character selection (unconfirmed)
function OnUnload():Void { delete efdCartographer; } // May as well be tidy
