# Script name:   	check_ms_iis_application_pool.ps1
# Version:          v0.01.160310
# Created on:    	10/03/2016																		
# Author:        	D'Haese Willem
# Purpose:       	Checks Microsoft Windows process count, cpu and memory usage
# On Github:		https://github.com/willemdh/check_ms_iis_application_pool
# On OutsideIT:		https://outsideit.net/check-ms-iis-application-pool
# Recent History:       	
#	10/03/16 => Initial creation
# Copyright:
#	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published
#	by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. This program is distributed 
#	in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A 
#	PARTICULAR PURPOSE. See the GNU General Public License for more details. You should have received a copy of the GNU General Public 
#	License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires –Version 2.0

$DebugPreference = 'Continue'
$VerbosePreference = 'Continue'

$IISStruct = New-Object PSObject -Property @{
    StopWatch = [System.Diagnostics.Stopwatch]::StartNew();
    ProcessName = '';
    Minimum = '';
    Maximum = '';
    Duration = '';
    Exitcode = 3;
    ReturnString = 'UNKNOWN: Please debug the script...'
}

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)][string]$Log,
        [parameter(Mandatory=$true)][ValidateSet('Debug', 'Info', 'Warning', 'Error', 'Unknown')][string]$Severity,
        [parameter(Mandatory=$true)][string]$Message
    )
    $Now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss,fff'
    $LocalScriptName = split-path $MyInvocation.PSCommandPath -Leaf
    if ($Log -eq 'Undefined') {
        Write-Debug "${Now}: ${LocalScriptName}: Info: LogServer is undefined."
    }
    elseif ($Log -eq 'Verbose') {
        Write-Verbose "${Now}: ${LocalScriptName}: ${Severity}: $Message"
    }
    elseif ($Log -eq 'Debug') {
        Write-Debug "${Now}: ${LocalScriptName}: ${Severity}: $Message"
    }
    elseif ($Log -eq 'Output') {
        Write-Host "${Now}: ${LocalScriptName}: ${Severity}: $Message"
    }
    elseif ($Log -match '^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])(?::(?<port>\d+))$' -or $Log -match "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$") {
        $IpOrHost = $log.Split(':')[0]
        $Port = $log.Split(':')[1]
        if  ($IpOrHost -match '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$') {
            $Ip = $IpOrHost
        }
        else {
            $Ip = ([System.Net.Dns]::GetHostAddresses($IpOrHost)).IPAddressToString
        }
        Try {
            $LocalHostname = ([System.Net.Dns]::GetHostByName((hostname.exe)).HostName).tolower()
            $JsonObject = (New-Object PSObject | 
                Add-Member -PassThru NoteProperty logsource $LocalHostname | 
                Add-Member -PassThru NoteProperty hostname $LocalHostname | 
                Add-Member -PassThru NoteProperty scriptname $LocalScriptName | 
                Add-Member -PassThru NoteProperty logtime $Now | 
                Add-Member -PassThru NoteProperty severity_label $Severity | 
                Add-Member -PassThru NoteProperty message $Message ) | 
                ConvertTo-Json
            $JsonString = $JsonObject -replace "`n",' ' -replace "`r",' '
            $Socket = New-Object System.Net.Sockets.TCPClient($Ip,$Port) 
            $Stream = $Socket.GetStream() 
            $Writer = New-Object System.IO.StreamWriter($Stream)
            $Writer.WriteLine($JsonString)
            $Writer.Flush()
            $Stream.Close()
            $Socket.Close()
        }
        catch {
            Write-Host "${Now}: ${LocalScriptName}: Error: Something went wrong while trying to send message to Logstash server `"$Log`"."
        }
        Write-Verbose "${Now}: ${LocalScriptName}: ${Severity}: Ip: $Ip Port: $Port JsonString: $JsonString"
    }
    elseif ($Log -match '^((([a-zA-Z]:)|(\\{2}\w+)|(\\{2}(?:(?:25[0-5]|2[0-4]\d|[01]\d\d|\d?\d)(?(?=\.?\d)\.)){4}))(\\(\w[\w ]*))*)') {
        if (Test-Path -Path $Log -pathType container){
            Write-Host "${Now}: ${LocalScriptName}: Error: Passed Path is a directory. Please provide a file."
            exit 1
        }
        elseif (!(Test-Path -Path $Log)) {
            try {
                New-Item -Path $Log -Type file -Force | Out-null	
            } 
            catch { 
                $Now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss,fff'
                Write-Host "${Now}: ${LocalScriptName}: Error: Write-Log was unable to find or create the path `"$Log`". Please debug.."
                exit 1
            }
        }
        try {
            "${Now}: ${LocalScriptName}: ${Severity}: $Message" | Out-File -filepath $Log -Append   
        }
        catch {
            Write-Host "${Now}: ${LocalScriptName}: Error: Something went wrong while writing to file `"$Log`". It might be locked."
        }
    }
}

Function Initialize-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args
    )
    try {
        For ( $i = 0; $i -lt $Args.count; $i++ ) { 
            $CurrentArg = $Args[$i].ToString()
            if ($i -lt $Args.Count-1) {
                $Value = $Args[$i+1];
                If ($Value.Count -ge 2) {
                    foreach ($Item in $Value) {
                        Test-Strings $Item | Out-Null
                    }
                }
                else {
                    $Value = $Args[$i+1];
                    Test-Strings $Value | Out-Null
                }
            } 
            else {
                $Value = ''
            }
            switch -regex -casesensitive ($CurrentArg) {
                "^(-P|--ProcessName)$" {
                    if ($value -match "^[a-zA-Z0-9._-]+$") {
                        $IISStruct.ProcessName = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-m|--Minimum)$" {
                    if ($value -match "^[0-9]{1,10}$") {
                        $IISStruct.Minimum = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-M|--Maximum)$" {
                    if ($value -match "^[0-9]{1,10}$") {
                        $IISStruct.Maximum = $Value
                    }
                    else {
                        throw "Method `"$value`" does not meet regex requirements."
                    }
                    $i++
                }
                "^(-h|--Help)$" {
                    Write-Help
                }
                default {
                    throw "Illegal arguments detected: $_"
                 }
            }
        }
    } 
    catch {
        Write-Host "CRITICAL: Argument: $CurrentArg Value: $Value Error: $_"
        Exit 2
    }
}
Function Test-Strings {
    Param ( [Parameter(Mandatory=$True)][string]$String )
    $BadChars=@("``", '|', ';', "`n")
    $BadChars | ForEach-Object {
        If ( $String.Contains("$_") ) {
            Write-Host "Error: String `"$String`" contains illegal characters."
            Exit $WsusStruct.ExitCode
        }
    }
    Return $true
} 

Function Invoke-CheckIISApplicationPool {
    Write-Log Verbose Info 'Invoke-CheckProcess launched.'

# Get-WmiObject -NameSpace 'root\WebAdministration' -class 'WorkerProcess' | Where-Object {$_.AppPoolName -match 'Test-Willem-01'}  | Select-Object -Expand ProcessId
# appcmd list wp

    $IISStruct.ExitCode = 0
    $IISStruct.ReturnString = 'Check MS Win Process finished successfully..'
}
#endregion Functions

#region Main

if ($Args) {
    if($Args[0].ToString() -ne "$ARG1$" -and $Args.count -ge 2){
            Initialize-Args $Args
            Invoke-CheckIISApplicationPool
    }
    else {
        $IISStruct.ReturnString = 'Script needs mandatory parameters to work.'
        $IISStruct.ExitCode = 2
    }
}
Write-Host $IISStruct.ReturnString
Exit $IISStruct.ExitCode

#endregion Main

