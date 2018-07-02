-- Credit: https://github.com/feldim2425/OC-Programs
local comp_layer = {};

local component = require("component");
local event = require("event");

comp_layer.init = function()
	comp_layer.c_internet = component.internet;
	if not comp_layer.c_internet then
		error("No Internet Card found");
	end
	
	if not comp_layer.c_internet.isTcpEnabled() then
		error("The TCP-Connections are disabled in the config file. Please contact the Server Owner.");
	end
	
	return true;
end

comp_layer.startTimer = function(callback, delay)
	return event.timer(delay, callback, math.huge);
end

comp_layer.stopTimer = function(handle)
	return event.cancel(handle);
end

comp_layer.open = function(address, port)
	
	local con = comp_layer.c_internet.connect(address,port);
	local st = false;
	repeat
		st,err = con.finishConnect();
		if err then
			error(err);
		end
	until st;
	
	return con;
end

comp_layer.sleep = function(sec)
  os.sleep(sec);
end

return comp_layer;