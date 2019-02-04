local component = require("component")
local serial = require("serialization")
local core = require("TabletOSCore")
local updater = {}
local fs = require("filesystem")
local serialization = require("serialization")
local thread = require("thread")
local internet
local pjctsURL = "https://raw.githubusercontent.com/HeroBrine1st/UniversalInstaller/master/projects.list"
if component.isAvailable("internet") then
	internet = component.internet
else
	--internet = require("TabletOSNetwork").tryToInetConnect()
	error("NO INTERNET CARD // NO INTERNET CONNECTION")
end
local metadata
if fs.exists("/TabletOS/.vMetadata") then
	local f = io.open("/TabletOS/.vMetadata","r")
	local data = f:read("*a")
	f:close()
	metadata = assert(load("return " .. data))()
end
if not metadata then
	metadata = {}
end
if not core.settings.updateChannel then
	core.settings.updateChannel = metadata.channel
else
	metadata.channel = core.settings.updateChannel
end
if not metadata.channel then
	metadata.channel = 1
	metadata.build = 0
end
local function request(options,handler)
	local success,response = pcall(internet.request,options.url,options.post,options.headers)
	if success then
		if response then
			local responseCode, responseName, responseHeaders
			while not responseCode do
				os.sleep(0)
				responseCode, responseName, responseHeaders = response.response()
			end
			local buffer = ""
			repeat
				os.sleep(0)
				local data, reason = response.read()
				if data then
					--print("Downloaded packet size ",#data)
					buffer = buffer .. data
				elseif reason then 
					response.close() 
					error(reason) 
				end
			until not data
			response.close()
			--print("Download complete")
			return handler(buffer,responseCode,responseName,responseHeaders)
		else
			error("No response!")
		end
	else
		--print("error",responce)
		os.sleep(1)
		error(responce)
	end
end

local function findUpdates()
	return request({
		url = pjctsURL,
	},function(data)
		data = assert(load("return " .. data))()
		for i = 1, #data do
			if data[i].name == "TabletOS" then
				local project = data[i]
				local channel = project.channels[metadata.channel]
				local filelist = channel.filelist
				return request({
					url = filelist,
				},function(data)
					data = assert(load("return " .. data))()
					if data.build > metadata.build then
						return data
					end
					return false
				end)
			end
		end
	end)
end

local function prepareToUpdate(filelist)
	os.sleep(0.1) --от даблклика, здесь реально важно
	thread.create(function()
		core.newNotification(0,"U",core.getLanguagePackages().Updater_downloadingUpdateStart,core.getLanguagePackages().Updater_downloadingUpdateStartDescription)
		fs.makeDirectory("/TabletOS/UpdateCache/")
		local f = io.open("/TabletOS/UpdateCache/updater-script","w")
		local cache = {}
		for i = 1, #filelist do
			local file = filelist[i]
			request({
				url = file.url,
			},function(data)
				local path = fs.concat("/TabletOS/UpdateCache/",file.path)
				fs.makeDirectory(fs.path(path))
				local fileStream = io.open(path,"w")
				fileStream:write(data)
				fileStream:close()
				f:write("echo(\"Copying " .. path .. " to " .. file.path .. "\")\n")
				f:write("copy(\"" .. path .. "\",\"" .. file.path .. "\")\n")
				f:write("progress(" .. tostring(i/#filelist*0.5) .. ")\n")
			end)
			cache[file.path] = true
		end
		for i = 1, #metadata.filelist do
			local filepath = metadata.filelist[i]
			core.log(2,"Updater",serialization.serialize(filepath))
			if not cache[filepath] then
				f:write("echo(\"Deleting " .. filepath .. "\")\n")
				f:write("delete(\"" .. filepath .. "\")\n")
				f:write("progress(" .. tostring(i/#metadata.filelist*0.4+0.5) .. ")\n")
			end
		end
		local _filelist = {}
		for i = 1, #filelist do
			local file = filelist[i]
			table.insert(_filelist,file.path)
		end
		f:write("echo(\"Updating metadata\")\n")
		f:write("file = read_file(\"/TabletOS/.vMetadata\")\n")
		f:write("metadata = parse(file)\n")
		f:write("metadata[\"build\"] = " .. tostring(filelist.build) .. "\n")
		f:write("metadata[\"filelist\"] = " .. serialization.serialize(_filelist) .. "\n")
		f:write("file = stringify(metadata);\n")
		f:write("write_file(\"/TabletOS/.vMetadata\",file)\n")
		f:write("progress(1)\n")
		f:write("echo(\"Success\")\n")
		f:close()
		local f2 = io.open("/TabletOS/UpdateCache/updater-binary","w")
		f2:write([[
			local a=require("filesystem")local b=require("serialization")local c=require("component").gpu;local d={}local e={progress=function(f)f=math.min(1,math.max(f,0))d.progress=f;if _G.progress then _G.progress(f)end end,write_file=function(g,h)local i=io.open(g,"w")i:write(h)i:close()end,read_file=function(g)local i=io.open(g)local h=i:read("*a")i:close()return h end,echo=function(j)print(j)end,copy=function(k,l)a.copy(k,l)end,delete=function(g)a.remove(g)end,abort=function(m)error(m)end,parse=function(n)return b.unserialize(n)end,stringify=function(o)return b.serialize(o)end,assert=assert}local p,p,q=require("TabletOSCore").getPackageDirectory()local i,r=loadfile(a.concat(a.path(q),"updater-script"),p,e)if not i then error(r)end;local s,t=pcall(i)if not s then error(t)end
		]])
		f2:close()
		core.newNotification(0,"U",core.getLanguagePackages().Updater_updateDownloaded,core.getLanguagePackages().Updater_rebootSystem)
	end):detach()
end

local updates = findUpdates()
if updates then
	--print("Updates got #2")
	updater.hasUpdate = true
	updater.lastVersName = updates.name or "No version name downloaded"
	updater.prepare = function() 
		prepareToUpdate(updates)
	end
else
	updater.prepare = function() end
end

return updater