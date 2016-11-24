package build;

import haxe.xml.Fast;
import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;

using Lambda;

class Cordova
{
	static function cordova(path:String, args:Array<String>)
	{
		Cli.cmdCompat('cordova', args, {logCommand:true, logOutput:true, workingDirectory:path});
	}

	static function plugman(path:String, args:Array<String>)
	{
		Cli.cmdCompat('plugman', args, {logCommand:true, logOutput:true, workingDirectory:path});
	}

	public static function run(config:Config, args:Array<String>)
	{
		switch (args[0])
		{
			case 'prepare': prepare(config);
			case 'build': build(config);
			case 'create-empty-template': createEmptyTemplate(config);
		}
	}

	static function build(config:Config)
	{
		var platform = config.getValue('cordova.platform');
		var path = config.getValue('cordova.path');
		var debug = config.getValue('define.debug', false) ? 'debug' : 'release';
		var emulator = config.getValue('define.emulator', false) ? 'emulator' : 'device';
		var prepare = config.getValue('define.prepare', false);
		var action = config.getValue('define.run', false) ? 'run' : 'build';
		if (prepare) cordova(path, ['prepare', platform]);
		else cordova(path, [action, platform, '--$debug', '--$emulator']);
	}

	static function prepare(config:Config)
	{
		var refresh = config.getValue('define.refreshPlugin', 'none');
		var platform = config.getValue('cordova.platform');
		var platformVersion = config.getValue('cordova.platformVersion', '');
		
		var path = config.getValue('cordova.path');
		var plugins = getPluginsList(config);

		var platformPath = '$path/platforms/$platform';

		if (!Cli.exists(platformPath))
			cordova(path, ['platform', 'add', platform + (platformVersion != '' ? '@$platformVersion' : '') ]);

		for (plugin in plugins)
			installCordovaPlugin(CordovaPluginMethod.DEFAULT, path, platform, plugin, refresh);
	}

	static function installCordovaPlugin(method: CordovaPluginMethod, path: String, platform:String, plugin:CordovaPlugin, refresh: String)
	{
		var exists = Cli.exists('$path/plugins/${plugin.id}');
		var shouldRefresh = refresh == 'all' || refresh == plugin.id;
		if (exists && !shouldRefresh) return;

		switch (method) {
			case PLUGMAN:
				plugman(path, [
					"install", 
					"--platform", platform, 
					"--plugin", plugin.path != null ? plugin.path : plugin.id, 
					"--project", Path.join(["platforms", platform]),
					"--plugins_dir", 'plugins_$platform' 
				]);

			default :
				var pluginPath = plugin.path == null ? plugin.id : plugin.path;
				if (exists) cordova(path, ['plugin', 'remove', plugin.id]);
				
				var args = ['plugin', 'add', pluginPath];
				if (plugin.args != null)
					args = args.concat(plugin.args);
				cordova(path, args);
		}
	}

	static function getPluginsList(config:Config):Array<CordovaPlugin>
	{
		var pluginConfigs = config.getValue('cordova.plugins', new Array<OrderedMap>());
		var plugins : Array<CordovaPlugin> = pluginConfigs.map(function(plugin){
			var id = plugin.get('id');
			var args = plugin.get('args');
			var path = plugin.get('path');
			if (path != null && Cli.exists(path))
				path = sys.FileSystem.fullPath(path);
			return {id:id, path:path, args:args};
		});
		return plugins;
	}

	static function createEmptyTemplate(config:Config)
	{
		var path = config.getValue('template.path');

		var pluginInstallMethod = Type.createEnum(CordovaPluginMethod, config.getValue("template.pluginInstallMethod", 'default').toUpperCase());

		/*
		 * we are using the android package name while creating the project
		 * because when adding the android version, 
		 * you must provide one. That's not the case with iOS
		 */
		if (FileSystem.readDirectory(path).length == 0)
			cordova(path, ["create", "./", config.getValue('android.packageName'), config.getValue('app.name')]);

		var plugins = getPluginsList(config);

		var platform = config.getValue('cordova.platform');
		var platformVersion = config.getValue('cordova.platformVersion', '');
	
		cordova(path, ["platform", "add", platform + (platformVersion != '' ? '@$platformVersion' : '') ]);

		// should be removed - gradle issue
		if (platform.indexOf("android") != -1)
			File.saveContent(Path.join([path, "platforms", "android", "gradle.properties"]), "android.useDeprecatedNdk=true");
		// ----
		
		/*
		 * we have to remove all plugin installed by cordova
		 * plugman installed and cordova installed plugin are not compatible together
		 */
		if (pluginInstallMethod == PLUGMAN)
		{
			var cmdResult = Cli.cmd('cordova', ["plugin", "list"], {logCommand:true, logOutput:true, workingDirectory:path});
			var cordovaInstalledPlugin = cmdResult.split("\n");
			for (installedPlugin in cordovaInstalledPlugin)
			{
				var infos = installedPlugin.split(" ");
				if (infos[0] != "")
					cordova(path, ["plugin", "remove", infos[0]]);
			}
		}

		var refresh = config.getValue('define.refreshPlugin', 'none');

		for (plugin in plugins)
			installCordovaPlugin(pluginInstallMethod, path, platform, plugin, refresh);
	}
}

enum CordovaPluginMethod {
	DEFAULT;
	PLUGMAN;
}

typedef CordovaPlugin = {
	var id: String;
	var args: Array<String>;
	var path: String;
}
