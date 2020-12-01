# Nagios plugin to check Microsoft IIS application pool states

### Idea

Checks Microsoft Windows IIS application pool state returning web application count, % CPU usage and memory usage.

### Screenshots

![IIS 01](/../screenshots/check-ms-iis-application-pool-outputs.png?raw=true "IIS Application Pool Outputs")

### Status

In production. 

### How To

-A,--ApplicationPool - ApplicationPool name
-ms,-minsites - Min site limit (def 0)
-APOD,--AppPoolOnDemand
-Appcmd,-AppCmd,-appcmd,-APPCMD

### Help

In case you find a bug or have a feature request, please make an issue on GitHub. 

### On Nagios Exchange

https://exchange.nagios.org/directory/Plugins/Web-Servers/IIS/Check-Microsoft-IIS-Application-Pool/details

### Copyright

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public 
License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later 
version. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the 
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more 
details at <http://www.gnu.org/licenses/>.
