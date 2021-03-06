﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-Cartographer
// Based off of the Preferences class of El Torqiro's ModUtils library:
//   https://github.com/eltorqiro/TSW-Utils
//   Copyright 2015, eltorqiro
//   Usage under the terms of the MIT License

import flash.geom.Point;

import com.GameInterface.DistributedValue;
import com.Utils.Archive;
import com.Utils.Signal;

import efd.Cartographer.lib.Mod;

// WARNING: Recursive or cyclical data layout is verboten.
//   A config setting holding a reference to a direct ancestor will cause infinite recursion during serialization.

// Basic types, Archive and Point all use built in serialization support
// Due to an implementation issue, arrays are being repacked as archives
//   (An array with one item, when saved with the default serialization method, is indistinguishable from a single variable)
// Object and Config Wrappers are also repacked into archives
//   To differentiate these uses of Archive the setting name "ArchiveType" is reserved for internal use
//   ConfigWrappers must decend directly from other ConfigWrappers, they won't load properly if nested within other types
//     TODO: This may be an issue, and should be fixed if possible

class efd.Cartographer.lib.ConfigWrapper {
	// ArchiveName is distributed value to be saved to for top level config wrappers
	// Leave archiveName undefined for nested config wrappers (unless they are saved seperately)
	// Also leave it undefined if loading/saving to the game's provided config.
	public function ConfigWrapper(archiveName:String) {
		ArchiveName = archiveName;
		Settings = new Object();
		SignalValueChanged = new Signal();
		SignalConfigLoaded = new Signal();
	}

	// Adds a setting to this config archive
	// - Archives are all or nothing affairs, it's not recommended to try and cherry pick keys as needed
	// - If a module needs to add additional settings it should either:
	//   - Provide a subconfig wrapper, if the settings are specific to the mod
	//   - Provide its own archive, if it's a static module that can share the settings between uses
	public function NewSetting(key:String, defaultValue):Void {
		if (key == "ArchiveType") { TraceMsg("'" + key + "' is a reserved setting name."); return; } // Reserved
		if (Settings[key] != undefined) { TraceMsg("Setting '" + key + "' redefined, existing definition will be overwritten."); }
		if (IsLoaded) { TraceMsg("Setting '" + key + "' added after loading archive will have default values."); }
		Settings[key] = {
			value: CloneValue(defaultValue),
			defaultValue: defaultValue
		};
		// Dirty flag not required
		// Worst case: An unsaved default setting is changed by an upgrade
	}

	public function DeleteSetting(key:String):Void {
		delete Settings[key];
		DirtyFlag = true;
	}

	// Get a reference to the setting (value, defaultValue) tuple object
	// Useful if a subcomponent needs to view but not change a small number of settings
	// Hooking up ValueChanged event requires at least temporary access to Config object
	public function GetSetting(key:String):Object {
		if (Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		return Settings[key];
	}

	// If changes are made to a returned reference the caller is responsible for setting the dirty flag and firing the value changed signal
	public function GetValue(key:String) { return GetSetting(key).value; }

	// Not a clone, allows direct edits to default object
	// Use ResetValue in preference when resetting values
	public function GetDefault(key:String) { return GetSetting(key).defaultValue; }

	public function SetValue(key:String, value) {
		var oldVal = GetValue(key);
		if (oldVal != value) {
			// Points cause frequent redundant saves and are easy enough to compare
			if (value instanceof Point && oldVal.equals(value)) { return oldVal; }
			Settings[key].value = value;
			DirtyFlag = true;
			SignalValueChanged.Emit(key, value, oldVal);
		}
		return value;
	}

	// Leave state undefined to toggle a flag
	public function SetFlagValue(key:String, flag:Number, state:Boolean):Number {
		var flags:Number = GetValue(key);
		switch (state) {
			case true: { flags |= flag; break; }
			case false: { flags &= ~flag; break; }
			case undefined: { flags ^= flag; break; }
		}
		return SetValue(key, flags);
	}

	public function ResetValue(key:String):Void {
		var defValue = GetDefault(key);
		if (defValue instanceof ConfigWrapper) { GetValue(key).ResetAll(); }
		else { SetValue(key, CloneValue(defValue)); }
	}

	public function ResetAll():Void {
		for (var key:String in Settings) { ResetValue(key);	}
	}

	// Notify the config wrapper of changes made to the internals of composite object settings
	public function NotifyChange(key:String):Void {
		DirtyFlag = true;
		SignalValueChanged.Emit(key, GetValue(key)); // oldValue cannot be provided
	}

	// Allows defaults to be distinct from values for reference types
	private static function CloneValue(value) {
		if (value instanceof ConfigWrapper) {
			// No need to clone a ConfigWrapper
			// The slightly faster reset call isn't worth two extra copies of all the defaults
			return value;
		}
		if (value instanceof Point) { return value.clone(); }
		if (value instanceof Array) {
			var clone = new Array();
			for (var i:Number = 0; i < value.length; ++i) {
				clone[i] = CloneValue(value[i]);
			}
			return clone;
		}
		if (value instanceof Object) {
			// Avoid feeding this things that really shouldn't be cloned
			var clone = new Object();
			for (var key:String in value) {
				clone[key] = CloneValue(value[key]);
			}
			return clone;
		}
		// Basic type
		return value;
	}

	// Should almost always have an archive parameter,
	// But a specified ArchiveName overrides the provided source
	public function LoadConfig(archive:Archive):Void {
		if (ArchiveName != undefined) { archive = DistributedValue.GetDValue(ArchiveName); }
		FromArchive(archive);
	}

	public function SaveConfig():Archive {
		if (IsDirty || !IsLoaded) {
			UpdateCachedArchive();
			if (ArchiveName != undefined) { DistributedValue.SetDValue(ArchiveName, CurrentArchive); }
		}
		return CurrentArchive;
	}

	// Reloads from cached archive, resets to last saved values, rather than default
	public function Reload():Void {
		if (!IsLoaded) { TraceMsg("Config never loaded, cannot reload."); return; }
		LoadConfig(CurrentArchive);
	}

	// Updates the cached CurrentArchive if dirty
	private function UpdateCachedArchive():Void {
		delete CurrentArchive;
		CurrentArchive = new Archive();
		CurrentArchive.AddEntry("ArchiveType", "Config");
		for (var key:String in Settings) {
			var value = GetValue(key);
			var pack = Package(value);
			if (!(value instanceof ConfigWrapper && value.ArchiveName != undefined)) {
				// Only add the pack if it's not an independent archive
				CurrentArchive.AddEntry(key, pack);
			}
		}
		DirtyFlag = false;
	}

	private static function Package(value:Object) {
		if (value instanceof ConfigWrapper) { return value.SaveConfig(); }
		if (value instanceof Archive) { return value; }
		if (value instanceof Point) { return value; }
		if (value instanceof Array || value instanceof Object) {
			var wrapper:Archive = new Archive();
			var values:Archive = new Archive();
			wrapper.AddEntry("ArchiveType", value instanceof Array ? "Array" : "Object");
			for (var key:String in value) {
				values.AddEntry(key, Package(value[key]));
			}
			wrapper.AddEntry("Values", values);
			return wrapper;
		}
		return value; // Basic type
	}

	private function FromArchive(archive:Archive):Void {
		if (archive != undefined) {
			for (var key:String in Settings) {
				var element:Object = archive.FindEntry(key,null);
				if (element == null) { // Could not find the key in the archive, likely a new setting
					var value = GetValue(key);
					if (value instanceof ConfigWrapper) {
						// Either of these, both of which can be Loaded
						//   Nested config saved as independent archive
						//   New sub-config
						value.LoadConfig();
					} else {
						TraceMsg("Setting '" + key + "' could not be found in archive. (New setting?)");
					}
					continue;
				}
				var savedValue = Unpack(element, key);
				if (savedValue != null) { SetValue(key, savedValue); }
			}
			CurrentArchive = archive;
			DirtyFlag = false;
		} else {
			CurrentArchive = new Archive(); // Nothing to load, but we tried
			CurrentArchive.AddEntry("ArchiveType", "Config"); // Remember to flag this as a config archive, in case we get saved as an invalid setting
		}
		SignalConfigLoaded.Emit();
	}

	private function Unpack(element:Object, key:String) {
		if (element instanceof Archive) {
			var type:String = element.FindEntry("ArchiveType", null);
			if (type == null) {
				return element;	// Basic archive
			}
			switch (type) {
				case "Config":
					// Have to use the existing config, as it has the field names defined
					// TODO: This only works for uniform config nesting, it doesn't support configs nested in other types
					GetValue(key).FromArchive(element);
					if (key == undefined) {
						ErrorMsg("A config archive could not be linked to an immediate parent.");
					}
					return null;
				case "Array":
				case "Object": // Serialized general type
					var value = type == "Array" ? new Array() : new Object();
					var values:Archive = element.FindEntry("Values");
					for (var index:String in values["m_Dictionary"]) {
						value[index] = Unpack(values.FindEntry(index));
					}
					return value;
				default:
				// Archive type is not supported
				//   Caused by reversion when a setting has had its type changed
				//   A bit late to be working this out though
					TraceMsg("Setting '" + key + "' was saved with a type not supported by this version. Default values will be used.");
					return null;
			}
		}
		return element; // Basic type
	}

	private static function TraceMsg(msg:String, options:Object):Void {
		if (options == undefined) { options = new Object(); }
		options.system = "Config";
		Mod.TraceMsg(msg, options);
	}

	private static function ErrorMsg(msg:String, options:Object):Void {
		if (options == undefined) { options = new Object(); }
		options.system = "Config";
		Mod.ErrorMsg(msg, options);
	}

	public function get IsLoaded():Boolean { return CurrentArchive != undefined; }

	// Checks if this, or any nested Config settings object, is dirty
	public function get IsDirty():Boolean {
		if (DirtyFlag == true) { return true; }
		for (var key:String in Settings) {
			var setting = GetValue(key);
			// In theory a nested independent archive could be saved by itself, without touching the main archive
			// but most usages will just save the main and expect it to save everything.
			// Could be expanded into a tri-state so it could skip down to the relevant sections on save.
			if (setting instanceof ConfigWrapper && setting.IsDirty) { return true; }
		}
		return false;
	}

	public var SignalValueChanged:Signal; // (settingName:String, newValue, oldValue):Void // Note: oldValue may not always be available
	public var SignalConfigLoaded:Signal;

 	// The distributed value archive saved into the game settings which contains this config setting
	// Usually only has a value for the root of the config tree
	// Most options should be saved to the same archive, leaving this undefined in child nodes
	// If a secondary archive is in use, providing a value will allow both archives to be unified in a single config wrapper
	// Alternatively a config wrapper may elect to forgo the names, and offload the actual archive load/save through parameters
	// Parameters take precidence over names
	private var ArchiveName:String;
	private var Settings:Object;

	// A cache of the last loaded/saved archive
	private var CurrentArchive:Archive;
	private var DirtyFlag:Boolean = false;
}
