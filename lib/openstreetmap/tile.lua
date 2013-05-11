--
-- OpenStreetMap tile handling library
--
--
-- Copyright (C) 2013, Hiroshi Miura
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU Affero General Public License for more details.
--
--    You should have received a copy of the GNU Affero General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
local bit = require 'bit'

local atan = math.atan
local tan = math.tan
local pi = math.pi
local sinh = math.sinh
local cos = math.cos
local rad = math.rad
local deg = math.deg
local floor = math.floor
local log = math.log
local tonumber = tonumber
local pairs = pairs
local io_open = io.open
local io_read = io.read
local io_close = io.close
local io_seek = io.seek
local ngx_header = ngx.header
local ngx_log = ngx.log
local ngx_print = ngx.print

module(...)

_VERSION = '0.10'

local mt = { __index = _M }

-- tile to lon/lat
function num2deg(x, y, zoom)
    local n = 2 ^ zoom
    local lon_deg = x / n * 360.0 - 180.0
    local lat_rad = atan(sinh(pi * (1 - 2 * y / n)))
    local lat_deg = deg(lat_rad)
    return lon_deg, lat_deg
end

-- lon/lat to tile
function deg2num(lon, lat, zoom)
    local n = 2 ^ zoom
    local lon_deg = tonumber(lon)
    local lat_rad = rad(lat)
    local xtile = floor(n * ((lon_deg + 180) / 360))
    local ytile = floor(n * (1 - (log(tan(lat_rad) + (1 / cos(lat_rad))) / math.pi)) / 2)
    return xtile, ytile
end

-- tile cordinate scale to zoom
function zoom_num(x, y, z, zoom)
    if z > zoom then
        local nx = bit.rshift(x, z-zoom)
        local ny = bit.rshift(y, z-zoom)
        return nx, ny
    elseif z < zoom then
        local nx = bit.lshift(x, zoom-z)
        local ny = bit.lshift(y, zoom-z)
        return nx, ny
    end
    return x, y
end

function is_inside_region(region, x, y, z)
    -- check inclusion of polygon
    local nx, ny = zoom_num(x, y, z, 20)
    local includes = nil
    for _, b in pairs(region) do
        local x1=nil
        local y1 = nil
        local tmp_inc = true
        for _, v in pairs(b) do
            local x2, y2 = deg2num(v.lon, v.lat, 20)
            if x1 ~= nil then
                local res = (y1 - y2) * nx + (x2 - x1) * ny + x1 * y2 - x2 * y1
                if res < 0 then
                    tmp_inc = nil
                end
            end
            x1=x2
            y1=y2
        end
        if tmp_inc == true then
            includes = true
        end
    end
    return includes
end


-- function: xyz_to_filename
-- arguments: int x, y, z
-- return: filename of metatile
--
function xyz_to_metatile_filename (x, y, z) 
    local res=''
    local v = 0
    local mx = x - x % 8
    local my = y - y % 8
    for i=0, 4 do
        v = bit.band(mx, 0x0f)
        v = bit.lshift(v, 4)
        v = bit.bor(v, bit.band(my, 0x0f))
        mx = bit.rshift(mx, 4)
        my = bit.rshift(my, 4)
        res = '/'..tostring(v)..res
    end
    return tostring(z)..res..'.meta'
end

-- get offset value from buffer
-- buffer should be string
-- offset is from 0-
-- s:byte(o) is counting from 1-
local function get_offset (buffer, offset)
    return ((buffer:byte(offset+4) * 256 + buffer:byte(offset+3)) * 256 + buffer:byte(offset+2)) * 256 + buffer:byte(offset+1)
end

-- function send_tile
-- arguments map, x, y, z
-- return ngx.OK or nil
-- 
--  send back tile to client from metatile
--
function send_tile(filename, x, y)
    local imgfile = filename
    local fd, err = io_open(imgfile,"rb")
    if fd == nil then
        return nil, err
    end
    local metatile_header_size = 532 -- XXX: 20 + 8 * 64
    local header, err = io_read(fd, metatile_header_size)
    if header == nil then
        io_close(fd)
        return nil, err
    end
    -- offset: lookup table in header
    local pib = 20 + ((y % 8) * 8) + ((x % 8) * 8 * 8 )
    local offset = get_offset(header, pib)
    local size = get_offset(header, pib+4)
    io_seek(fd, "set", offset)
    local png, err = io_read(fd, size)
    if png == nil then
        io_close(fd)
        return nil, err
    end
    ngx_header.content_type = 'image/png'
    ngx_print(png)
    io_close(fd)
    return true
end

local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        error('attempt to write to undeclared variable "' .. key .. '"')
    end
}

setmetatable(_M, class_mt)
