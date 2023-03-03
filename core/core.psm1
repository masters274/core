<#
        .Synopsis
        Module that extends core functionality in powershell. 

        .DESCRIPTION
        Module with various generic functions that could be used in any script
        
        .NOTES
        Code reuse saves time!
        
        .COMPONENT
        Core
        
        .ROLE
        Fill gaps in general use
        
        .FUNCTIONALITY
        General Powershell functionality extension

        .AUTHOR
        Chris Masters - https://github.com/masters274
#>


#region Custom Shared Types 

$sbMkLinkType = {
    <#
            lpSymlinkFileName = [String] Path/name where you wan the link to be placed
            lpTargetFileName = [String] File or folder path you want linked to
            dwFlags = [int] 0 for file, and 1 for directory. Use logic to figure this out instead of asking
    #>
    
    $typDef = @'
        using System;
        using System.Runtime.InteropServices;
  
        namespace mklink
        {
            public class symlink
            {
                [DllImport("kernel32.dll", EntryPoint="CreateSymbolicLink")]
                public static extern bool CreateSymbolicLink(string lpSymlinkFileName, string lpTargetFileName, int dwFlags);
                
                [DllImport("kernel32.dll", EntryPoint="CreateHardLink")]
                public static extern bool CreateHardLink(string lpSymlinkFileName, string lpTargetFileName, IntPtr lpSecurityAttributes);
            }
        }
'@
    Try {
        $null = [mklink.symlink]
    } 
        
    Catch {
        Add-Type -TypeDefinition $typDef
    }
}


& $sbMkLinkType

#endregion


#region : DEVELOPMENT FUNCTIONS 


Function Test-ModuleLoaded {
    <#
            .SYNOPSIS
            Checks that all required modules are loaded.

            .DESCRIPTION
            Receives an array of strings, which should be the module names. 
            The function then checks that these are loaded. If the required
            modules are not loaded, the function will try to load them by name
            via the default module path. Function returns a failure if it's
            unable to load any of the required modules.

            .PARAMETER RequiredModules
            Parameter should be a string or array of strings.

            .PARAMETER Quiet
            Avoids output to the screen.

            .EXAMPLE
            Test-ModuleLoaded -RequiredModules "ActiveDirectory"
            Verifies that the ActiveDirectory module is loaded. If not, it will attempt to load it.
            if this fails, a $false will be returned, otherwise, a $true will be returned. 
            
            $arrayModules = ('ActiveDirectory','MyCustomModule')
            $result = Test-ModuleLoaded -RequiredModules $arrayModules

            Checks if the two modules are loaded, or loadable, if so, $result will contain a value of
            $true, otherwise it will contain the value of $false.

            .NOTES
            None yet.

            .LINK
            https://github.com/masters274/

            .INPUTS
            Requires at the very least, a string name of a module.

            .OUTPUTS
            Returns success or failure code ($true | $false), depending on if required modules are loaded.
    #>
    [CmdletBinding()]
    Param 
    (
        [Parameter(Mandatory = $true, HelpMessage = 'String array of module names')]
        [String[]]$RequiredModules,
        [Switch]$Quiet
    ) 

    
    Process {
        # Variables
        $boolDebug = $PSBoundParameters.Debug.IsPresent
        $loadedModules = Get-Module
        $availableModules = Get-Module -ListAvailable
        [int]$failedModules = 0
        [System.Collections.ArrayList]$missingModules = @()
        $arraryRequiredModules = $RequiredModules
        
        # Loop thru all module requirements
        Foreach ($module in $arraryRequiredModules) {
            Invoke-DebugIt -Message 'Module' -Value $module -Console
            
            IF ($loadedModules.Name -contains $module) {
                $true | Out-Null 
            } 
            
            ElseIF (($availableModules.Name -ccontains $module) -or ($null = Test-Path -Path $module)) {
                Import-Module -Name $module
            }
            
            Else {
                Invoke-DebugIt -Message 'Missing module' -Value $module -Console
                
                $missingModules.Add($module)
                $failedModules++
            }
        }
        
        # Return the boolean value for success for failure
        if ($failedModules -gt 0) {
            Write-Error -Message 'Failed to load required modules'
        } 
        
        else {
            IF (!($Quiet)) {
                return $true
            }
        }
    }
}


Function Invoke-VariableBaseLine {
    <#
            .SYNOPSIS
            A function used to keep your environment clean.

            .DESCRIPTION
            This function, when used at the beginning of a script or major setup of functions, will snapshot
            the variables within the local scope. when ran for the second time with the -Clean parameter, usually
            at the end of a script, will remove all the variables created during the script run. This is helpful
            when working in ISE and you need to run your script multiple times while building. You don't want 
            prexisting data to end up in the second run. Also when you have an infinite loop script that you need
            the environment clean after each call to something. 

            .PARAMETER Clean
            The name says it all...

            .EXAMPLE
            Invoke-VarBaseLine -Clean
            This will clean up all the variables created between the start and finish callse of this function

            .NOTES
            This ain't rocket surgery :-\

            .LINK
            https://github.com/masters274/

            .INPUTS
            N/A.

            .OUTPUTS
            Void.
    #>


    
    [CmdletBinding()]
    Param 
    (
        [Switch]$Clean
    )
    
    Begin {
        if ($Clean -and -not $baselineLocalVariables) {
            Write-Error -Message 'No baseline variable is set to revert to.'
        }
    }
    
    Process {
        # logger -Console -Force -Value $(($MyInvocation.Line).split(' ')[1]).Trim() 
        
        if ($Clean) {
            Compare-Object -ReferenceObject $($baselineLocalVariables.Name) -DifferenceObject `
            $((Get-Variable -Scope 0).Name) |
            Where-Object { $_.SideIndicator -eq '=>' } |
            ForEach-Object { 
                Remove-Variable -Name ('{0}' -f $_.InputObject) -ErrorAction SilentlyContinue
            }
        }
        
        else {
            $Global:baselineLocalVariables = Get-Variable -Scope Local
        }
    }
    
    End {
        if ($Clean) {
            Remove-Variable -Name baselineLocalVariables -Scope Global -ErrorAction SilentlyContinue
        }
    }
}


Function Add-Signature {
    # Signs a file using the first code signing cert in your personal store
    # ./makecert -n "PowerShell Local CertificateRoot" -a sha1 -eku 1.3.6.1.5.5.7.3.3 -r -sv root.pvk root.cer -ss Root -sr localMachine 
    # ./makecert -n "PowerShell tux" -ss MY -a sha1 -eku 1.3.6.1.5.5.7.3.3 -iv root.pvk -ic root.cer
    
    Param
    (
        [string] $File = $(throw "Please specify a filename.")
    )
    
    # $cert = @(Get-ChildItem cert:\CurrentUser\My | where-object { $_.FriendlyName -eq "MyCodeSigningCert" }) #[0] #-codesigning)[0]
    $cert = (Get-ChildItem Cert:currentuser\my\ -CodeSigningCert |
        Select-Object -First 1)

    # check if the file is a PowerShell file, if not, fix it... 
    $srtExt = ( Get-ChildItem -Path $File | 
        ForEach-Object { $_.Extension } )

    IF ($srtExt -ne '.ps1') {
        # we want to be able to sign any file that we can write to... 

        # rename the file
        Get-ChildItem -Path $File | Rename-Item -NewName { $_.Name -replace "$srtExt$" , ".ps1" }
        
        # get the temporary file name
        $strTempName = [io.path]::ChangeExtension($File, "ps1")
        
        # sign the file with the new name
        Set-AuthenticodeSignature $strTempName $cert
        
        # change the file name back to the original
        Get-ChildItem -Path $strTempName | Rename-Item -NewName { $_.Name -replace ".ps1$" , "$srtExt" }
    } 
    
    Else {
        # just sign the file... 
        Set-AuthenticodeSignature $File $cert
    }
}


Function Invoke-EnvironmentalVariable {
    <#
            .Synopsis
            Short description

            .DESCRIPTION
            Long description

            .EXAMPLE
            Example of how to use this cmdlet

            .EXAMPLE
            Another example of how to use this cmdlet
    #>

    <#
            Version 0.1
            - Day one, it's my berphday!
    #>

    [CmdLetBinding()]
    [CmdletBinding(DefaultParameterSetName = 'Get')]
    Param
    (
        [Parameter(Mandatory = $true, Position = 0,                
            HelpMessage = 'Name of the variable')]
        [String] $Name,
        
        [Parameter(Position = 1,
            HelpMessage = 'Value of the variable')]
        $Value,
        
        [Parameter(Mandatory = $false, Position = 2,
            HelpMessage = 'Select the scope you require.')]
        [ValidateSet('Machine', 'User', 'Process')]
        [String]$Scope = 'User',
        
        [ValidateSet('Get', 'Set', 'Remove', 'New')]
        [String]$Action = 'Get'
    )
    
    Begin {
        # Baseline our environment 
        #Invoke-VariableBaseLine

        # Debugging for scripts
        [Bool] $boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process {
        # Variables
        [String] $strCommand = '[Environment]::GetEnvironmentVariable($Name,$Scope)'
        [String] $strFunctionCalledName = $MyInvocation.InvocationName
        [Bool] $boolIsAdmin = Test-AdminRights
    
        Invoke-DebugIt -Message 'Command text' -Value $strCommand -Console
        Invoke-DebugIt -Message 'Function called name' -Value $strFunctionCalledName -Console
        Invoke-DebugIt -Message 'Admin?' -Value $boolIsAdmin -Console
        Invoke-DebugIt -Message 'first item in command pipe' -Value $MyInvocation.InvocationName -Console
        
        IF (
            $Action -eq 'Set' -or $Action -eq 'New' -or `
                $strFunctionCalledName -eq 'Set-EnvVar' -or `
                $strFunctionCalledName -eq 'Set-EnvironmentalVariable' -or `
                $strFunctionCalledName -eq 'New-EnvVar' -or `
                $strFunctionCalledName -eq 'New-EnvironmentalVariable'
        ) {
            $Action = 'Set' # setting casue the default is get, and messes with logic later. 
            IF ($Value) {
                [String] $strCommand = '[Environment]::SetEnvironmentVariable("{0}","{1}","{2}")' -f `
                    $Name, $Value, $Scope
            }
            
            Else {
                Write-Error -Message ('{0} : Value is required when using "Set"' -f $strFunctionCalledName)
                Return
            }
        }
        
        ElseIF (
            $Action -eq 'Remove' -or `
                $strFunctionCalledName -match 'Remove-EnvVar' -or `
                $strFunctionCalledName -match 'Remove-EnvironmentalVariable'
        ) {
            $Action = 'Remove' # setting casue the default is Get, and messes with logic later. 
            [String] $strCommand = 'Remove-Item -Path Env:\{0}' -f $Name
        }
        
        IF ($boolIsAdmin -or ($Scope -eq 'User' -or $Scope -eq 'Process' -or $Action -eq 'Get')) {
            Invoke-Expression -Command $strCommand
        }
            
        Else {
            Invoke-Elevate -Command $strCommand -Persist
        }
    }
    
    End {
        # Clean up the environment
        #Invoke-VariableBaseLine -Clean
    }
}


Function ConvertTo-Hexadecimal { 
    Param
    (
        [ValidateScript({ Test-Path -Path $_ -PathType 'Leaf' })]
        [String] $FilePath
    )
    
    # Converts a file to hexadecimal string. 
    
    [byte[]] $hex = Get-Content -Encoding byte -Path $FilePath # C:\path\to\file.exe
    # [System.IO.File]::WriteAllLines(".\hexdump.txt", ([string]$hex)) # Ouput HEX to file
	
    [String] $hex
}


Function ConvertFrom-Hexadecimal {
    # Converts hexadecimal string to ASCII. 
    Param
    (
        [String]$HexString
    )
    
    # Variables
    $Encoder = [System.Text.Encoding]::ASCII

    [Byte[]] $strTemp = $HexString -Split ' '
    
    $Encoder.GetString($strTemp)
}


Function ConvertFrom-HexToFile {
    # Converts hexadecimal string to file. 
    # PS > [byte[]] $hex = gc -encoding byte -path C:\path\to\file.exe
    # PS > [System.IO.File]::WriteAllBytes(".\hexdump.txt", ([string]$hex))
    
    Param
    (
        [String]$HexString, 
        
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [String] $FilePath
    )
    
    # Variables
    $strfilename = $FilePath | Split-Path -Leaf
    
    Try {
        #$objDirectory = gci ($FilePath | Split-Path -Parent)
    
        $strDirectory = (Get-Item -Path $($FilePath | Split-Path -Parent)).FullName
    }
    
    Catch {
        $strDirectory = $pwd.Path 
    } 
    
    $file = "$strDirectory\$strfilename"

    [Byte[]] $strTemp = $HexString -Split ' '
    
    [System.IO.File]::WriteAllBytes($file, $strTemp) # NOTE: MUST BE FULL FILE PATH!
}


Function ConvertFrom-Base36 {
    Param 
    (
        [Parameter(valuefrompipeline = $true, 
            HelpMessage = 'Alphadecimal string to convert')]
        [string] $Base36Num = ''
    )
    
    $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    $inputarray = $base36Num.tolower().tochararray()
    [array]::reverse($inputarray)
    [long]$decNum = 0
    $pos = 0

    foreach ($c in $inputarray) {
        $decNum += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
        $pos++
    }
    $decNum
}


Function ConvertTo-Base36 {
    Param 
    (
        [Parameter(valuefrompipeline = $true, 
            HelpMessage = 'Integer number to convert')]
        [int] $DecNum
    )
    
    $alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    Do {
        $remainder = ($DecNum % 36)
        $char = $alphabet.substring($remainder, 1)
        $base36Num = "$char$base36Num"
        $DecNum = ($DecNum - $remainder) / 36
    }
    While ($DecNum -gt 0)

    $base36Num
}


Function ConvertFrom-Base64 {
    Param
    (
        [String] $InputString
    )
    
    $bytes = [System.Convert]::FromBase64String($InputString)
    $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)

    $decoded
}


Function ConvertTo-Base64 {
    Param
    (
        [String] $InputString
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $encoded = [System.Convert]::ToBase64String($bytes)

    $encoded
}


Function Convert-ByteArrayToHex {
    Param 
    (
        $ByteArray
    )

    If ($ByteArray.GetType().Name -eq 'Byte[]') {
        [String] $Bytes = $ByteArray -Join ' '
    }
    Else {
        $Bytes = $ByteArray
    }
    
    [String] $strReturnValue = $null 

    ForEach ($Byte In $Bytes.ToString().Split(' ') ) {
        $strReturnValue += '0x' + [Convert]::ToString($Byte, 16).ToUpper().PadLeft(2, '0') + ','
    }
    
    $($strReturnValue | % { "0x$_" }) -Replace "^0x|\,$", ''
}


New-Alias -Name Add-Sig -Value Add-Signature -ErrorAction SilentlyContinue
New-Alias -Name sign -Value Add-Signature -ErrorAction SilentlyContinue
New-Alias -Name Set-EnvVar -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue
New-Alias -Name Get-EnvVar -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue
New-Alias -Name Set-EnvironmentalVariable -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue
New-Alias -Name Get-EnvironmentalVariable -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue
New-Alias -Name New-EnvVar -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue
New-Alias -Name Remove-EnvVar -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue
New-Alias -Name Remove-EnvironmentalVariable -Value Invoke-EnvironmentalVariable -ErrorAction SilentlyContinue

#endregion


#region : FILE SYSTEM FUNCTIONS 


Function Invoke-Touch {
    Param
    (
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = 'File path', ValueFromPipeline = $true)]
        [String]$Path,
        
        [Parameter(Position = 2, HelpMessage = 'Force directory')]
        [Switch] $Directory,
        
        [Switch]$Quiet
    )
    
    Begin {

    }
	
    Process {
        $strPath = $Path

        # See if we can figure out if asking for file or directory
        if ("$($strPath -replace '^\.')" -like '*.*' -and -not $Directory) { 
            $strType = 'File'
        } 
        
        Else { 
            $strType = 'Directory'
        }

        if ((Test-Path "$strPath") -eq $true) {
            If ("$strType" -match 'File') {
                (Get-ChildItem $strPath).LastWriteTime = Get-Date
            } 
        }
    
        Else {
            If ($Quiet) {
                $null = New-Item -Force -ItemType $strType -Path "$strPath"
            }
            
            Else {
                New-Item -Force -ItemType $strType -Path "$strPath"
            }
        }
    }
    
    End {
        
    }
}


Function Open-NotepadPlusPlus {
    Param
    (
        [Parameter(Mandatory = $true)]
        [Alias('Path', 'FN')]
        [String[]]$FileName
    )
    
    Process {
        [String] $strProgramPath = "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
        IF (Test-Path -Path $strProgramPath) {
            & $strProgramPath $FileName
        }
        
        Else {
            Write-Error -Message 'It appears that you do not have Notepad++ installed on this machine'
        }
    }
}


Function New-SymLink {
    <#
            .Synopsis
            Creates symbolic links

            .DESCRIPTION
            This provides similar functionality to *nix ln command

            .EXAMPLE
            New-SymLnk -Link .\MyNewShortCut -Target '\\DataShareServer\MyShare'

            .EXAMPLE
            ln .\shortcut ..\FileIcantLiveWithOut.txt

            .NOTES
            This function requires elevation
    #>

    <#
            Version 0.2
            - Using DLL Import instead of calls to mklink.exe
    #>

    [CmdLetBinding()]
    Param
    (
        [Parameter(Position = 0)]
        [ValidateScript({ Split-Path $_ -Parent | Test-Path })]
        [String] $Link,
        
        [Parameter(Position = 1)]
        [ValidateScript({ Test-Path $_ })]
        [String] $Target
    )
    
    Begin {
        # Baseline our environment 
        #Invoke-VariableBaseLine
        
        # Stop on error action
        $ErrorActionPreference = 'Stop'

        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
        
        # Check if this is an elevated prompt
        [bool] $boolIsAdmin = $(Test-AdminRights)
        
        # Check that our DLL import exists
        Try {
            $null = [mklink.symlink]
        }
        
        Catch {
            Write-Error -Message '[mklink.symlink] type not loaded' 
        }
        
        # Check if the link/file already exists.
        IF (Test-Path -Path $Link) {
            Write-Error -Message ('{0} already exists!' -f $Link)
        }
    }
    
    Process {
    
        <# 
                If (Test-Path -PathType Container $Target)
                {
                $strCommand = "cmd /c mklink /d"
                }
    
                Else
                {
                $strCommand = "cmd /c mklink"
                }
                Invoke-Expression -Command ('{0} {1} {2}' -f $strCommand, $Link, $Target)
        #>
        
        # Variables 
        $boolResult = $null
        
        $linkPath = Get-item -Path $(Split-Path -Path "$Link" -Parent)
        IF ($linkPath -eq $null) { $linkPath = $PWD.Path + '\' + ($Link | Split-Path -Leaf) } 
        Else { $linkPath = $linkPath.FullName + '\' + $($link | Split-Path -Leaf) }
        
        $TargetPath = "$((Get-Item -Path $Target).FullName)"
        
        If (Test-Path -PathType Container $Target) {
            [int] $dwFlag = 1
            
            [String] $dwType = 'Directory'
        }
    
        Else {
            [int] $dwFlag = 0
            
            [String] $dwType = 'File'
        }
        
        Invoke-DebugIt -Console -Message 'DW Type' -Value "$dwType"
        
        $strCommand = '$boolResult = [mklink.symlink]::CreateSymbolicLink("{0}","{1}",{2})' -f $linkPath, $TargetPath, $dwFlag
        
        IF ($boolIsAdmin) {
            Invoke-Expression -Command $strCommand
        }
        
        Else {
            # Ask if we should elevate...
            Invoke-DebugIt -Console -Value 'This command requires elevation. Press "Y" to attempt elevation.' -Force
            
            $response = Read-Host -Prompt 'Continue (Y/N)?'
            
            IF ($response -eq 'Y') {
                $strRemoteCommand = @"
Import-Module -name Core; 

$($strCommand);

IF (!`$boolResult)
{
    Invoke-DebugIt -Console -Message 'Status' -Value 'Failed to create link!' -Color 'Red' -Force
}

Else
{
    Invoke-DebugIt -Console -Message 'Success' -Value 'Link created successfully' -Color 'Green' -Force
}
"@
                Invoke-Elevate -Command $strRemoteCommand -Persist
            }
            
            Else {
                Invoke-DebugIt -Console -Value "Couldn't get it done, huh?" -Color 'Yellow' -Force 
            }
        }
        
    
        
        
        IF ($boolResult = $false) {
            Invoke-DebugIt -Console -Force -Message 'Failed' -Value 'Unable to create link!' -Color 'red'
        }
        
        Else {
            Invoke-DebugIt -Console -Message 'Success' -Value $boolResult -Color 'Green'
        }
    }
    
    End {
        # Clean up the environment
        #Invoke-VariableBaseLine -Clean
    }
}


Function Remove-SymLink {
    Param
    (
        [String] $Link
    )
    
    If (Test-Path -PathType Leaf $Link) {
        $strCommand = "Remove-Item -Path $Link -Force"
    }
    
    Else {
        $dir = Get-Item -Path $Link
        $strCommand = '[System.IO.Directory]::Delete("{0}")' -f $dir
        # Making a system.io call due to junction handling in < POSH 6
    }

    Invoke-Expression -Command ('{0}' -f $strCommand)
}


Function New-HardLink {
    <#
            .Synopsis
            Creates a new hard link to a file.

            .DESCRIPTION
            Hard links are mappings, or system representation of a file in a single volume. 

            .EXAMPLE
            New-HardLink -Link "$PSModulesPath\MyPoshMod\MyPoshMod.psm1" -Target 'C:\Modueles\MyPoshMod.psm1'

            .EXAMPLE
            New-HardLink .\testfile.txt ..\test.txt

            .NOTES
            You cannot make a link to a folder in any drive/volume, or link to a file in another drive/volume.
    #>

    <#
            Version 0.1
            - Day one.
    #>

    [CmdLetBinding()]
    Param
    (
        [Parameter(Mandatory = $true, Position = 0,
            HelpMessage = 'New hard link to be created')]
        [ValidateScript({ (!(Test-Path $_)) })]
        [String] $Link,
        
        [Parameter(Mandatory = $true, Position = 1,
            HelpMessage = 'Path to existing target file')]
        [ValidateScript({ Test-Path $_ })]
        [String] $Target
    )
    
    Begin {
        # Baseline our environment 
        #Invoke-VariableBaseLine
        
        # Set the error action preference
        $ErrorActionPreference = 'Stop'

        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process {
        # Variables
        $strTargetPath = (Get-Item -Path $Target).FullName
        $strLinkPath = Get-item -Path $(Split-Path -Path "$Link" -Parent)
        
        IF ($strLinkPath -eq $null) { $strLinkPath = $PWD.Path + '\' + ($Link | Split-Path -Leaf) } 
        Else { $strLinkPath = $strLinkPath.FullName + '\' + $($link | Split-Path -Leaf) }
        
        $boolResult = [mklink.symlink]::CreateHardLink("$strLinkPath", "$strTargetPath", 0)
        
        IF ($boolResult) {
            Invoke-DebugIt -Console -Message 'Success' `
                -Value ('Hard link {0} created successfully' -f $strLinkPath) -Color 'Green'
        }
        
        Else {
            Invoke-DebugIt -Console -Force -Message 'Failed' -Value 'Unable to create hard link!' -Color 'red'
        }
    }
    
    End {
        # Clean up the environment
        #Invoke-VariableBaseLine -Clean
    }
}


Function Get-HardLink {
    <#
            .SYNOPSIS
            List/find files with multiple hardlinks.

            .DESCRIPTION
            works well to find out if one of your hardlinks, created by New-HardLink, have been broken. 

            .PARAMETER Path
            Path to file which we would like to list hardlinks for

            .EXAMPLE
            Get-HardLink -Path C:\files\myFile.txt
            Returns the count and list of hardlinks and boolean value of multiple links

            .NOTES
            Thanks to Greg Shields for this function.

            .LINK
            http://www.itninja.com/blog/user/greg_shields
    #>



    [CmdLetBinding()]
    Param
    (
        [Parameter(Position = 0, Mandatory = $True, HelpMessage = "Enter a filename and path",
            ValueFromPipeline = $True)]
        $Path
    )

    Process {
        #if a file is piped in get the full file name and path
        if ($path.GetType().Name -eq "FileInfo") {
            $filepath = $path.fullname
        }
        elseif ($path.GetType().Name -eq "DirectoryInfo") {
            Write-verbose "Skipping folder $path"
            return
        }
        else {
            #otherwise assume it is a string
            $filepath = $path
        }
    
        #Verify path
        Write-Verbose "Testing $filepath"
        If (Test-Path $filepath) {
            $links = fsutil hardlink list $filepath
            $count = ($links | Measure-Object).Count
            If ($count -gt 1) {
                #more than one hard link found
                Write-Verbose "Found multiple links"
                $Multiple = $True
            }
            else {
                $Multiple = $False
            }
        
            Write-Verbose "Creating custom object"
        
            New-Object -TypeName PSObject -Property @{
                Path          = $filePath
                Links         = $links
                Count         = $count
                MultipleLinks = $Multiple
            }
        }
        Else {
            Write-Warning "Failed to find $filepath"
        }
    }

}


Function ConvertFrom-DosToUnix {
    <#
            .Synopsis
            Covert carriage returns to new line

            .DESCRIPTION
            Converts text files from DOS to Unix file new lines

            .EXAMPLE
            dox2unix .\test.txt

            .EXAMPLE
            ConvertFrom-DosToUnix -FilePath C:\Users\Me\Documents\MyFolderWithStuff\myDosFileWithText.txt
    #>
    
    Param
    (
        [Parameter(Mandatory = $true, HelpMessage = 'Path to file', Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType 'Leaf' })]
        [String] $FilePath
    )
    
    # get the full path to the file
    $strFilePath = $(Get-ChildItem -Path $FilePath | ForEach-Object { $_.FullName })
	
    # get the contents of the file to convert 
    $strTempContents = [IO.File]::ReadAllText($strFilePath) -replace "`r`n", "`n"
	
    # set the contents of the file 
    [IO.File]::WriteAllText($strFilePath, $strTempContents)
}


Function Set-DirectoryOwner {
    Param
    (
        [Parameter( Mandatory = $true )]
        [ValidateScript({
                Try {
                    $Folder = Get-Item $_ -ErrorAction Stop
                }
                Catch [System.Management.Automation.ItemNotFoundException] {
                    Throw [System.Management.Automation.ItemNotFoundException] "${_} Maybe there are network issues?"
                }
                If ($Folder.PSIsContainer) {
                    $True
                } 
                Else {
                    Throw [System.Management.Automation.ValidationMetadataException] "The path '${_}' is not a container."
                }
            })] [String] $FolderPath,
        
        [Parameter( Mandatory = $true, 
            Position = 0, 
            HelpMessage = 'DOMAIN\Username', 
            ValueFromPipeline = $true, 
            ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('.\\.')]
        [String] $UserName
    )
    
    $acl = Get-Acl $FolderPath.FullName
    
    [String] $domain = $UserName.Split('\')[0].Trim()
    [String] $uname = $UserName.Split('\')[1].Trim()

    $owner = [System.Security.Principal.NTAccount]::new($domain, $uname)

    If ($acl.Owner.ToString().Trim() -ne $UserName) {
        $acl.SetOwner($owner)

        Set-Acl -Path $FolderPath -aclobject $acl 
    }
    Else {
        '{0} is already the owner of this directory'
    }
}



New-Alias -Name npp -Value Open-NotepadPlusPlus -ErrorAction SilentlyContinue
New-Alias -Name touch -Value Invoke-Touch -ErrorAction SilentlyContinue
New-Alias -Name ln -Value New-SymLink -ErrorAction SilentlyContinue 
New-Alias -Name Create-SymbolicLink -Value New-SymLink -ErrorAction SilentlyContinue
New-Alias -Name dos2unix -Value ConvertFrom-DosToUnix -ErrorAction SilentlyContinue

#endregion


#region : LOG/ALERT FUNCTIONS 


Function Invoke-Snitch {
    <#
            .SYNOPSIS
            Describe purpose of "Invoke-Snitch" in 1-2 sentences.

            .DESCRIPTION
            Add a more complete description of what the function does.

            .PARAMETER strMessage
            This is a required variable. Message that is sent.

            .EXAMPLE
            Invoke-Snitch -strMessage Value
            Describe what this call does

            .NOTES
            Requires that you set, somewhere in your environment: smtphost, emailto, emailfrom, and emailsubject

            .LINK
            URLs to related sites
            The first link is opened by Get-Help -Online Invoke-Snitch

            .INPUTS
            Requires a string message.

            .OUTPUTS
            Void.
    #>

    # Function to send an email alert to distro-list
	
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [string]$strMessage
    )
    

    # Check that the required variables are set in the environment
    if ($smtphost -and $emailto -and $emailfrom -and $emailsubject -and $strMessage) {
        Send-MailMessage -SmtpServer $smtphost -To $emailto -From $emailfrom -Subject $emailsubject `
            -BodyasHTML ('{0}' -f $strMessage)
        
    } 
    
    else {
    
        Write-Error -Message 'Not all required variables are set to invoke the snitch!'
    }
}
    
Function Invoke-DebugIt {
    <#
            .SYNOPSIS
            A more visually dynamic option for printing debug information.

            .DESCRIPTION
            Quick function to print custom debug information with complex formatting.

            .PARAMETER msg
            Descripter for the value to be printed. Color is gray.

            .PARAMETER val
            Emphasized "value" output for quick visibility when debugging. Default
            color of value is Cyan. Intentionally left as undefined variable type to
            avoid errors when presenting various types of data, possibly forgetting to
            add ToString() to the end of someting like an integer. 

            .PARAMETER Color
            Used when you need to categorize/differentiate, visually, types of values.
            Default color is Cyan.

            .PARAMETER Console
            Used when you want to log to the console. Can be used when logging to file as well. 

            .PARAMETER Logfile
            Used to log output to file. Logged as CSV

            .EXAMPLE
            Invoke-DebugIt -msg "Count of returned records" -val "({0} -f $($records.count)) -color Green
            Assuming that the number of records returned would be five, the following would be printed to
            the screen. Count of returned records : 5

            The message would be gray, and the number 5 would be Cyan, providing contrasting emphasis.

            .NOTES
            Pretty easy to understand. Just give it a try :)

    #>
    <#    
            CHANGELOG:
    
            ver 0.2
            - Changed parameters to full name
            - Added aliases to the parameters so older scripts would continue to function
            - Added the ability to log to file
            - Added -Console switch parameter for specifying output type
            - Added logic for older scripts that are not console switch aware

            ver 0.3
            - Takes value from pipeline
            - Added positional values to parameters
            - Changed type accelerator from .NET [Boolean] to PowerShell [Bool]
            - Added application event log, logging.

    #>
	
    [CmdletBinding()]
    Param
    (
        [Parameter(
            Position = 0)]
        [Alias('msg', 'm')]
        [String] $Message,
        
        [Parameter(
            ValueFromPipeline = $true,
            Mandatory = $false,
            Position = 1)]
        [Alias('val', 'v')]
        $Value,
        
        [Alias('c')]
        [String] $Color,
        
        [Alias('f')]
        [Switch] $Force, # Log even if the Debug parameter is not set
        
        [Alias('con')]
        [Switch] $Console, # Should we log to the console
        
        [Switch] $EvetLog, # Add an entry to the Application Event log
        
        [int] $EventId = 60001, # Default event log ID
        
        [ValidateScript({ Test-Path -Path ($_ | Split-Path -Parent) -PathType Container })]
        [Alias('log', 'l')]
        [String] $Logfile
    )
    
    $ScriptVersion = '0.3'
    #[Bool] $boolDebug = $PSBoundParameters.Debug.IsPresent
    
    If (!($Console -and $Logfile)) {
        # Backward compatible logic
        $Console = $true
    }
    
    IF ($Console) {
        If ($Color) {
            $strColor = $Color
        } 
        
        Else {
            $strColor = 'Cyan'
        }
    
        If ($boolDebug -or $Force) {
            Write-Host -NoNewLine -f Gray ('{0}{1} : ' -f (Get-Date).ToString('yyyyMMdd_HHmmss : '), ($Message)) 
            Write-Host -f $($strColor) ('{0}' -f ($Value))
        }
    }
    
    If ($Logfile.Length -gt 0) {
        $strSender = ('{0},{1},{2}' -f (Get-Date).ToString('yyyyMMdd_HHmmss'), $Message, $Value)
        $strSender | Out-File -FilePath $Logfile -Encoding ascii -Append
    }
    
    IF ($EvetLog) {
        [String] $strSource = 'PoshLogger'
        [String] $strEventLogName = 'Application'
        
        # Check if the source exists
        IF (!(Get-EventLog -Source $strSource -LogName $strEventLogName -Newest 1)) {
            # Check if running as Administrator
            $boolAdmin = Test-AdminRights
            IF ($boolAdmin) {
                New-EventLog -LogName $strEventLogName -Source $strSource
            }
            
            Else {
                Invoke-Elevate -ScriptBlock { New-EventLog -LogName $strEventLogName -Source $strSource }
            }
        }
        
        Write-EventLog -LogName $strEventLogName -Source $strSource -EventId $EventId -Message ($Message + $Value)
    }
}


Function Invoke-Alert {
    <#
            .Synopsis
            Audible tone that can be easily called when some event is triggered. 

            .DESCRIPTION
            Great for monitoring things in the background, when you need to be working on something else. 

            .PARAMETER Duration
            This is the count or duration in seconds that the tone will be generated. A value of zero will
            beep until interrupted. Negative integers will beep only once. 

            .EXAMPLE
            The following will beep 3 times when the listed IP is reachable
            While (!(Test-Connection 8.8.8.8 -Q -C 1)) { sleep -s 1 }; Alert

            .EXAMPLE
            The following will beep once the IP is reachable, until you close the window, or Ctrl+C
            While (!(Test-Connection 8.8.8.8 -Q -C 1)) { sleep -s 1 }; Alert -c 0
    #>

    <#
            Version 0.1
            - Day one
    #>

    Param
    (
        [Parameter(Position = 0)]
        [Alias('Count', 'c', 'Number', 'n')]
        [Int]$Duration = 3
    )
    
    Process {
        # Variables
        $i = 0
    
        Do {
            [console]::Beep(1000, 700)
            Start-Sleep -Seconds 1
            
            If ($Duration -gt 0) { $i++ }
        }
        While ($i -lt $Duration) 
    }
}


New-Alias -Name logger -Value Invoke-DebugIt -ErrorAction SilentlyContinue
New-Alias -Name Invoke-Logger -Value Invoke-DebugIt -ErrorAction SilentlyContinue
New-Alias -Name Alert -Value Invoke-Alert -ErrorAction SilentlyContinue

#endregion


#region : SECURITY FUNCTIONS 


Function Test-AdminRights {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole] 'Administrator')
}


Function Start-ImpersonateUser {
    Param
    (
        [Parameter(Mandatory = $true, HelpMessage = 'Scriptblock to be ran')]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $true, HelpMessage = 'User to impersonate')]
        [String]$Username,
        
        [ValidateScript({ Test-Connection -ComputerName $_ -Quiet -Count 4 })]
        [String]$ComputerName,
        
        [PSCredential]$Credential
    )
    
    Begin {

    }
    
    Process {
    
        # Variables 
        [bool] $boolHidden = $true
        [String] $strCommandExec = 'powershell'
        [String] $strCommand = "& { $ScriptBlock }"
        [String] $strEncodedCommand = [Convert]::ToBase64String($([System.Text.Encoding]::Unicode.GetBytes($strCommand)))
        [String] $strArguments = "-Nop -W Hidden -Exec ByPass -EncodedCommand $strEncodedCommand"
        [String] $strJobName = ('ImpersonationJob{0}' -f (Get-Random))
        [String] $strTempFileName = [Guid]::NewGuid().ToString('d')
        [String] $strTempFilePath = ('{0}\{1}' -f $env:TEMP, $strTempFileName)
        [String] $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo />
  <Triggers />
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings />
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>$($boolHidden.ToString().ToLower())</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$strCommandExec</Command>
      <Arguments>$strArguments</Arguments>
    </Exec>
  </Actions>
  <Principals>
    <Principal id="Author">
      <UserId>$Username</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
</Task>
"@

        Try {
            $xml | Set-Content -Encoding Ascii -Path $strTempFilePath -Force
            $ErrorActionPreference = 'Stop'
            
            $s = New-CimSession -ComputerName $ComputerName -Credential $Credential
            
            
            $strCommandBaseCreate = 'SCHTASKS.exe /Create /TN $strJobName /XML $strTempFilePath /S $ComputerName'
            $strCommandBaseRun = 'SCHTASKS.exe /Run /TN $strJobName /S $ComputerName'
            $strCommandBaseDelete = 'SCHTASKS.exe /Delete /TN $strJobName /S $ComputerName /F'

            
            If ($Credential) {
                $strCommandCredential = (
                    '/U {0} /P ''{1}''' -f $Credential.UserName, $Credential.GetNetworkCredential().Password
                )
                
                Invoke-Expression -Command ('{0} {1}' -f $strCommandBaseCreate, $strCommandCredential)
                Invoke-Expression -Command ('{0} {1}' -f $strCommandBaseRun, $strCommandCredential)
                Invoke-Expression -Command ('{0} {1}' -f $strCommandBaseDelete, $strCommandCredential)
            }
            
            Else {
                Invoke-Expression -Command ('{0}' -f $strCommandBaseCreate)
                Invoke-Expression -Command ('{0}' -f $strCommandBaseRun)
                Invoke-Expression -Command ('{0}' -f $strCommandBaseDelete)
            }
        }
        
        Catch {
            Write-Error -Message ('Failed to run scheduled task on computer: {0}' -f $ComputerName)
        }

        Finally {
            Remove-Item -Path $strTempFilePath -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            Remove-CimSession -CimSession $s
        }
    }
    
    End {
        
    }
}


Function Get-LoggedOnUser {
    [CmdletBinding()]             
    Param              
    (                        
        [Parameter( Mandatory,
            ValueFromPipeline,                           
            ValueFromPipelineByPropertyName
        )] 
        [Alias('Name', 'IPAddress')]
        [String[]]$ComputerName,
        
        [Parameter(Mandatory = $true, HelpMessage = 'Admin creds for remote computer')]
        [System.Management.Automation.Credential()]
        [PSCredential] $Credential,

        [Switch] $ShowEmpty
    )
 
    Begin {

        $wmiParams = @{
            Class       = 'Win32_Process'
            Filter      = "Name='sihost.exe' OR Name='logonUI.exe'" 
            ErrorAction = 'Stop'
        }
        
        If ($Credential) {
            $wmiParams += @{ Credential = $Credential } 
        }

        function Get-IdleInfo {

            Param (

                $processInfo
            )

            foreach ($proc in $processInfo) {

                if ($proc.Name -eq 'logonUI.exe') {

                    $id = $proc.SessionID

                    $idleTime = ([WMI] '').ConvertToDateTime($proc.CreationDate)

                    return @{
                        Id       = $id 
                        IdleTime = $idleTime
                    }
                }
            }
        }
    }
           
    Process { 
        Foreach ($Computer in $ComputerName) {
            $processinfo = @(Get-WmiObject @wmiParams -ComputerName $Computer)
                
            If ($processinfo.Name -contains 'sihost.exe') {
                
                # Need to get the idle info first, if exists
                $idleInfo = Get-IdleInfo -processInfo $processinfo
                
                $processinfo | Foreach-Object { 

                    if ($_.Name -eq 'LogonUI.exe') {
                        return
                    }
                    
                    $pi = $_ 
                    $pi.GetOwner() 
                } |  
                Where-Object { $_ -notcontains 'NETWORK SERVICE' -and $_ -notcontains 'LOCAL SERVICE' -and $_ -notcontains 'SYSTEM' } | 
                Sort-Object -Unique -Property User | 
                ForEach-Object { 

                    $dt = ([WMI] '').ConvertToDateTime($pi.CreationDate)
                    $idleTime = $( 
                        
                        if ($idleInfo.Id -eq $pi.SessionId) { 

                            $t = New-TimeSpan -Start $idleInfo.IdleTime -End ([datetime]::now)

                            '{0}d {1}h {2}m {3}s' -f $t.Days, $t.Hours, $t.Minutes, $t.Seconds
                        } 
                        else { 
                            $null 
                        }
                    )

                    $ld = New-TimeSpan -Start $dt -End ([datetime]::now)
                    $logonDuration = '{0}d {1}h {2}m {3}s' -f $ld.Days, $ld.Hours, $ld.Minutes, $ld.Seconds

                    New-Object psobject -Property @{ 
                        
                        Computer      = $Computer
                        Domain        = $_.Domain
                        User          = $_.User
                        SessionId     = $pi.SessionId
                        CreationDate  = $dt 
                        LogonDuration = $logonDuration
                        Idle          = $(if ($idleInfo.Id -eq $pi.SessionId) { $true } else { $false })
                        IdleTime      = $idleTime
                    } 
                } |  
                Select-Object Computer, Domain, User, SessionId, CreationDate, LogonDuration, Idle, IdleTime
            }
            Else {
                
                if ($ShowEmpty) {
                    
                    New-Object psobject -Property @{ 
                        
                        Computer      = $Computer
                        Domain        = $null
                        User          = $null
                        SessionId     = $null
                        CreationDate  = $null 
                        LogonDuration = $null
                        Idle          = $null
                        IdleTime      = $null
                    } 
                }
                else {
                    $false
                }
            }
        }
    }
}


Function Invoke-Elevate {
    <#
            TODO: 
            - have output return to the main screen
            - launch the elevated process with wscript to avoid UAC
            - work out an elevated prompt, and all commands ran will use elevation until...
    #>
    [CmdLetBinding()]
    [CmdletBinding(DefaultParameterSetName = 'Command')]
    Param
    (
        # ScriptBlock: Negates the need for Command
        [Parameter(Mandatory = $false, ParameterSetName = "Command")]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ScriptBlock',                
            HelpMessage = 'Scriptblock of commands to be executed')]
        [ScriptBlock] $ScriptBlock,
        
        # Command: Negates the need for ScriptBlock
        [Parameter(Mandatory = $false, ParameterSetName = 'ScriptBlock')]
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Command',
            HelpMessage = 'Commands to be executed')]
        [String] $Command,
        
        [Switch] $NoProfile,
        
        [Switch] $Persist
    )
    
    Begin {
        # Invoke-VariableBaseLine
        
        [Bool] $boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process {
    
        [String] $strCommand = "& { $ScriptBlock }"
 
        IF ($Command) {
            [String] $strCommand = $Command
        }
        
        [String] $strEncodedCommand = [Convert]::ToBase64String($([System.Text.Encoding]::Unicode.GetBytes($strCommand)))
        [String] $strArguments = "-Exec ByPass -EncodedCommand $strEncodedCommand"
        
        IF ($NoProfile) {
            $strArguments = + ' -Nop'
        }
        
        IF ($Persist) {
            $strArguments += ' -NoExit'
        }
    
        Start-Process PowerShell -Verb runas -ArgumentList $strArguments
    }
    
    End {
        # Invoke-VariableBaseLine -Clean
    }
}


Function Invoke-CredentialManager {
    <#
            .Synopsis
            Function for managing credentials for storage

            .DESCRIPTION
            Used to both store, and retreive a password from an XML file

            .EXAMPLE
            Invoke-CredentailManager -FilePath .\MySshPassord.auth
	
            Gets (if exists) or stores credentials in .\MySshPassword.auth. Will prompt for credentials if the 
            file does not exist. 

            .EXAMPLE
            Invoke-CredentailManager -FilePath .\MySshPassord.auth -Credentail $creds

            Stores the credentials from object "$creds" into a file in the local directory

            .EXAMPLE
            $strCreds = Get-Password .\test.xml 
			
            PS C:\> $strCreds.Username
            Me@myDomain.local

            PS C:\> $strCreds.Password
            VewySecwetPassw0rd!
    #>

    <#
            Version 0.2
            - ? MACD. Move, add, change, or delete details go here. ?
            - Change : Added storing user name
            - Change : Cred file format changed to XML
            - Add    : Backward compat with older script calls
    #>
    
    [CmdLetBinding()]
    Param
    (
        [Parameter(Mandatory = $true, Position = 0,
            HelpMessage = 'Path to where the credentials files is stored')]
        [Alias('CredentialsFile')]
        [string]$FilePath,
        
        [Parameter(Position = 1)]
        [PSCredential]$Credential,
        
        [Switch] $ReturnCredObject # Only for XML objects
    )
    
    Begin {
        # Baseline our environment 
        #Invoke-VariableBaseLine

        # Global debugging for scripts
        $boolDebug = $PSBoundParameters.Debug.IsPresent
    }
    
    Process {
        # Variables
        $CredentialsFile = $FilePath
		
		
		
        # Check to see if the file exists 
        IF (-not (Test-Path $credentialsfile)) { 
            # If not, then prompt user for the credential 
            IF ($Credential) {
                $creds = $Credential
            }
        
            Else {
                $creds = Get-Credential 
            }
        
            $userName = $creds.UserName
            $encpassword = $creds.password 
        
            # Create the file so we can get the full name
            Invoke-Touch -Path $CredentialsFile -Quiet
			
            # Must have the full path to save the XML file 
            $strOutputFile = (Get-Item -Path $CredentialsFile).FullName
			
            [xml] $credXml = @"
<cred>
	<uname>$($userName)</uname>
	<pass>$($encpassword | ConvertFrom-SecureString)</pass>
</cred>
"@
			
            $credXml.Save($strOutputFile)
        }
    
        Else {
            # Check if we're working with XML or old
            Try {
                [xml] $xmlFile = Get-Content -Path $CredentialsFile
                $boolXml = $true
                $user = $xmlFile.cred.uname
                $encpassword = $xmlFile.cred.pass | ConvertTo-SecureString
            }
		
            Catch {
                $encpassword = Get-Content -Path $credentialsfile | ConvertTo-SecureString
            }
			
            # Use the Marshal classes to create a pointer to the secure string in memory 
            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($encpassword) 
    
            # Change the value at the pointer back to unicode (i.e. plaintext) 
            $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)  
    
            If ($boolXml) {
                If ($ReturnCredObject) {
                    $objCred = New-Object -TypeName PSCredential (
                        $user, $encpassword
                    )
                    
                    $objCred
                }
                
                Else {
                    # Build and object and return it. 
                    $objBuilder = New-Object -TypeName PSObject
                    $objBuilder | Add-Member -MemberType NoteProperty -Name 'Username' -Value $user
                    $objBuilder | Add-Member -MemberType NoteProperty -Name 'Password' -Value $pass
				
                    $objBuilder
                }
            }
			
            Else {
                # Return the decrypted password 
                $pass 
            }
            
        }
    }
    
    End {
        # Clean up the environment
        #Invoke-VariableBaseLine -Clean
        Remove-Variable -Name pass -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        
        [GC]::Collect()
    }
}


New-Alias -Name elevate -Value Invoke-Elevate -ErrorAction SilentlyContinue
New-Alias -Name sudo -Value Invoke-Elevate -ErrorAction SilentlyContinue
New-Alias -Name Store-Credentials -Value Invoke-CredentialManager -ErrorAction SilentlyContinue
New-Alias -Name Get-Password -Value Invoke-CredentialManager -ErrorAction SilentlyContinue

#endregion


#region : SYSTEM FUNCTIONS


Function Get-InstalledSoftware {
    <#
            .Synopsis
            Get installed software on the local or remote computer. 

            .DESCRIPTION
            Uses the uninstall path to capture installed software. This is safer than using the WMI query, which
            checks the integrity upon query, and can often reconfigure, or reset application defaults. This 
            function is built to scale, for quick inventory of software across your environment. 

            .EXAMPLE
            $progs = Get-InstalledPrograms

            .EXAMPLE
            Get-InstalledPrograms | Select-Object -Property DisplayName, Publisher, InstallDate, Version |FT -Auto

            .EXAMPLE
            $swInventory = Get-InstalledSoftware -ComputerName 'cmp1','cmp2',sys3' -Credential $creds | 
            Group-Object -Property PSComputerName -AsHashTable -AsString; $swInventory['cmp1']
            
            This will return and object, with all listed computer's installed software. This makes it easy to 
            inventory your computers, and verify them later (if you Expot-CliXml, and Compare-Object later). 
            This can scale to very large networks
    #>

    [CmdLetBinding()]
    Param
    (
        [ValidateScript({ Test-Connection -ComputerName $_ -Quiet -Count 4 }) ]
        [String[]] $ComputerName,
        
        [System.Management.Automation.Credential()]
        [PSCredential] $Credential
    )
    
    Begin {
        # Baseline our environment 
        #Invoke-VariableBaseLine

        # Debugging for scripts
        $Script:boolDebug = $PSBoundParameters.Debug.IsPresent
        
        # List of required modules for this function
        $arrayModulesNeeded = (
            'Core'
        )
        
        # Verify and load required modules
        #Test-ModuleLoaded -RequiredModules $arrayModulesNeeded -Quiet
    }
    
    Process {
        # Variables
        [String] $strScriptBlock = 'Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Invoke-DebugIt -Console -Message 'ScriptBlock' -Value $strScriptBlock
    
        IF ($ComputerName) {
            If ($ComputerName.Count -gt 1) {
                Invoke-DebugIt -Message '[INFO]' -Value ('Computer count: {0}' -f $ComputerName.Count)
                [String] $ComputerName = $ComputerName -join ','
                
                Invoke-DebugIt -Message 'Computers' -Value $ComputerName
            }
            Else {
                Invoke-DebugIt -Message '[INFO]' -Value ('Computer count: {0}' -f $ComputerName.Count)
                [String] $ComputerName = $ComputerName[0].ToString()
            }
            
            Invoke-DebugIt -Console -Message 'Computer name is present' -Value $ComputerName
            
            $strScriptBlock = '{' + $strScriptBlock + '}'
            Invoke-DebugIt -Console -Message 'Scriptblock modified' -Value $strScriptBlock
            
            [String] $strCommand = 'Invoke-Command -ComputerName {0} -Command {1} -Authentication Kerberos' -f $ComputerName, $strScriptBlock
            Invoke-DebugIt -Console -Message 'String command' -Value $strCommand
        
            IF ($Credential) { 
                Invoke-DebugIt -Console -Message 'Credential is present' -Value $($Credential.UserName)
                
                $strCommand = $strCommand + ' -Credential $Credential' 
                Invoke-DebugIt -Console -Message 'String command' -Value $strCommand
            }
        }
    
        Else {
            Invoke-DebugIt -Console -Value 'Local machine query' -Color 'Blue'
            
            $strCommand = $strScriptBlock
            Invoke-DebugIt -Console -Message 'String command' -Value $strCommand
        }
    
        $arrayPrograms = Invoke-Expression -Command $strCommand
    
        $arrayPrograms
    }
    
    End {
        # Clean up the environment
        #Invoke-VariableBaseLine -Clean
    }
}


Function Get-UninstallString {
    <#
            .SYNOPSIS
            Gets the uninstall string for the searched for program.

            .DESCRIPTION
            This function returns the entire item properties for the matched program, if found in the uninstall key.
            Output is limited.

            .PARAMETER ComputerName
            Name of the remote computer(s) you wish to query. Accepts from the pipeline, and will accept an array.
            If omitted, will query the local machine

            .PARAMETER Pattern
            Full or partial name of an installed program, on the local or remote computer.

            .PARAMETER Credential
            If omitted will attempt to authenticate as domain, or stored credentials

            .EXAMPLE
            Get-UninstallString -ComputerName wrkst01 -Pattern 'Microsoft' -Credential $myCreds
            Will return the uninstall string for all programs matching Microsoft in the DisplayName field

            Get-UninstallString -ComputerName wrkst01,wrkst01 -Pattern 'Microsoft' -Credential $myCreds
            Will return the uninstall string for all programs matching Microsoft in the DisplayName field, from
            both computers queried

            Get-UninstallString -Pattern 'Microsoft'
            Will return the uninstall string for all programs matching Microsoft on the local machine

            .NOTES
            N/A.

            .LINK
            N/A

            .INPUTS
            Requires a string to search for

            .OUTPUTS
            Returns a PSCustomeObject, or an array of PSCustomObject
    #>


    Param
    (
        [Parameter(Mandatory = $true, HelpMessage = 'name to search for')]
        [String]$Pattern,
        
        [Parameter(ValueFromPipeline = $true)]
        [String[]] $ComputerName,
        
        [System.Management.Automation.Credential()]
        [PSCredential] $Credential
    )

    Begin {
        Function Script:Where-Match {
            Param
            (
                [Object]
                [Parameter(Mandatory = $true, ValueFromPipeline = $true, HelpMessage = 'Keys to filter')]
                $RegItem, 
                
                [Parameter(Mandatory = $true)]
                [String] $SearchString
            )
            
            Process {
                if ($RegItem.DisplayName -match ('{0}' -f $SearchString)) {
                    $RegItem
                }
            }
        }

        $strRegKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        $regCommand = 'Get-ChildItem -Path {0} | Get-ItemProperty' -f $strRegKey
        
        $sbRemoteKey = [ScriptBlock]::Create($regCommand)
        
        $Params = @{
            'ScriptBlock' = $sbRemoteKey
        }
        
        If ($Credential) {
            $Params.Add('Credential', $Credential)
        }
        
        # Too much info displayed by default... chop it down!
        [String[]] $defaultDisplaySet = @('DisplayName', 'UninstallString')
    
        $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet(
            'DefaultDisplayPropertySet', [string[]]$defaultDisplaySet
        )
        $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
    }
	
    Process {

        If ($ComputerName) {
            $Params.Add('ComputerName', $ComputerName)
        }

        $retVal = Invoke-Command @Params | Where-Match -SearchString $Pattern
        
        $retVal | Add-Member -MemberType MemberSet -Name 'PSStandardMembers' -Value $PSStandardMembers
        
        $retVal
    }
    
    End {
    
    }
}


Function Get-USB {
    <#     
            .Synopsis
            Gets USB devices attached to the system

            .Description
            Uses WMI to get the USB Devices attached to the system

            .Example
            Get-USB

            .Example
            Get-USB | Group-Object Manufacturer  

            .Notes
            Thanks Lee Holmes
    #>
    
    Get-WmiObject -Class Win32_USBControllerDevice | Foreach-Object { [Wmi]$_.Dependent }
}


Function Add-IPRemotingTrustedHost {
    Param
    (
        [String[]] $TrustedHosts = '*',
        
        [Switch] $Append
    )    
    
    $boolAdmin = Test-AdminRights
    
    $CurrentTrustedHosts = (Get-Item -Path WSMan:\localhost\Client\TrustedHosts).Value
    $arrayTrustedHosts = @()
    
    If ($Append -and $CurrentTrustedHosts -ne '') {
        $arrayTrustedHosts += $CurrentTrustedHosts
    }
    
    $arrayTrustedHosts += $TrustedHosts
    
    [String] $test = '"' + ($arrayTrustedHosts -join ',') + '"'
    
    [String] $strCommand = @"

[bool] `$boolServiceRunning = ((Get-Service -Name WinRM).Status -eq "Running");
        
If (!`$boolServiceRunning)
{
    Start-Service -Name WinRM
};
        
Set-Item WSMan:\localhost\Client\TrustedHosts -Value $test -Force;

"@
        
        
    [ScriptBlock] $sbCommand = [ScriptBlock]::Create($strCommand)
    
    If (!$boolAdmin) {
        $strTitle = 'Run as Administrator'
        $strMessage = 'This command requires administrative right. Wou you like to elevate?'
        $yes = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', `
            'Elevate and run the command'

        $no = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', `
            'Cancel request'

        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

        $result = $host.ui.PromptForChoice($strTitle, $strMessage, $options, 0)

        Switch ($result) {
            0 { Invoke-Elevate -ScriptBlock $sbCommand }
            1 { 'Exiting script' }
        }
    }
    Else {
        $sbCommand.Invoke()
    }
}


Function Get-IpRemotingTrustedHost {
    [CmdLetBinding()]
    Param
    ()
    
    $CurrentTrustedHosts = (Get-Item -Path WSMan:\localhost\Client\TrustedHosts).Value
    
    $CurrentTrustedHosts
}


Function Connect-Workstation {
    Param 
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String] $ComputerName,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.Management.Automation.Credential()]
        [PSCredential] $Credential,
        
        [ValidateSet('Default', 'Basic', 'CredSSP', 'Digest', 'Kerberos', 'Negotiate', 'NegotiateWithImplicitCredential')]
        [String] $Authentication = 'Kerberos'
    )
    
    $strComputerName = $ComputerName
    $UserCredential = $Credential
   
    Try {
        $null = [ipaddress] $ComputerName
        
        $objService = Get-Service -Name WinRM
        $arrayTrustedHosts = Get-IpRemotingTrustedHost -ErrorAction SilentlyContinue
        
        If ($objService.Status -eq 'Running' -and ($arrayTrustedHosts -contains '*' -or $arrayTrustedHosts -contains $ComputerName)) {
            Enter-PsSession -Credential $UserCredential -Authentication Default -ComputerName $strComputerName -EnableNetworkAccess
        }
        Else {
            Write-Error -Message 'WinRM is not configured properly to connect to IP addresses'
            Return
        }
    }
    Catch {
        Enter-PsSession -Credential $UserCredential -Authentication $Authentication  $strComputerName
    }
}


Function Clear-IECachedData {
    <#
            .SYNOPSIS
            Pretty easy to grasp... This function clears data cached by IE

            .DESCRIPTION
            Clears all, or selected cache data stored by IE

            .PARAMETER TempIEFiles
            Delete Temporary Internet Files

            .PARAMETER Cookies
            Delete Cookies

            .PARAMETER History
            Delete History

            .PARAMETER FormData
            Delete Form Data

            .PARAMETER Passwords
            Delete Passwords

            .PARAMETER All
            Delete All

            .PARAMETER AddOnSettings
            Delete Files and Settings Stored by Add-Ons

            .EXAMPLE
            Clear-IECachedData -TempIEFiles -Cookies -History -FormData -Passwords -All -AddOnSettings
            Describe what this call does

            .INPUTS
            N/A

            .OUTPUTS
            N/A
    #>


    
    [CmdletBinding(ConfirmImpact = 'None')]
    Param
    (
        [Parameter(HelpMessage = ' Delete Temporary Internet Files')]
        [switch] $TempIEFiles,
        
        [Parameter(HelpMessage = 'Delete Cookies')]
        [switch] $Cookies,
        
        [Parameter(HelpMessage = 'Delete History')]
        [switch] $History,
        
        [Parameter(HelpMessage = 'Delete Form Data')]
        [switch] $FormData,
        
        [Parameter(HelpMessage = 'Delete Passwords')]
        [switch] $Passwords,
        
        [Parameter(HelpMessage = 'Delete All')]
        [switch] $All,
        
        [Parameter(HelpMessage = 'Delete Files and Settings Stored by Add-Ons')]
        [switch] $AddOnSettings
    )
    
    if ($TempIEFiles) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 8 }
    if ($Cookies) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 2 }
    if ($History) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 1 }
    if ($FormData) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 16 }
    if ($Passwords) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 32 }
    if ($All) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 255 }
    if ($AddOnSettings) { & "$env:windir\system32\rundll32.exe" InetCpl.cpl, ClearMyTracksByProcess 4351 }
}


Function Get-ComObject {
    <#
            .SYNOPSIS
            Returns a list of COM objects with associated CLSID

            .DESCRIPTION
            This will allow you to search for full or partial CLSID. This is handy when troubleshooting DCOM
            errors from the event logs

            .EXAMPLE
            Get-ComObject
            Returns a list of COM objects and CLID

            .EXAMPLE
            Get-ComObject -CLID abcd
            Returns all COM objects that MATCH your string.

            .INPUTS
            String

            .OUTPUTS
            PSCustomObject. In the event more than one object is returned, and array of PSCustomObject
    #>
    
    [CmdLetBinding()]
    Param
    (
        [Parameter( Position = 0,
            HelpMessage = 'Full or partial CLSID',
            ParameterSetName = 'ScriptBlock'
        )] [Alias('ID', 'GUID')]
        [String] $CLSID,
        
        [Parameter( Position = 1,
            HelpMessage = 'Name of computer to manage',
            ValueFromPipeLine = $true
        )] [Alias('HostName', 'Host', 'System', 'Computer')]
        [String[]] $ComputerName,
        
        [System.Management.Automation.Credential()]
        [PSCredential] $Credential
    )
    
    Begin {
        $Params = @{ ArgumentList = $CLSID }
        
        If ($ComputerName) {
            $Params += @{ ComputerName = $ComputerName }
        }
        
        If ($Credential) {
            $Params += @{ Credential = $Credential }
        }
    }

    Process {
        [ScriptBlock] $sb = {
            
            Param ( [String] $CLSID ) 
        
            $ComObjects = Get-ChildItem HKLM:\Software\Classes -ErrorAction SilentlyContinue | 
            Where-Object {
                $_.PSChildName -match '^\w+\.\w+$' -and (Test-Path -Path "$($_.PSPath)\CLSID")
            } | 
            Select-Object -Property `
                PSChildName, `
            @{n = 'CLSID'; e = { (Get-ItemProperty ($_.PSPath + '\clsid')).'(default)' } }

            $ComObjects | Where-Object { $_.CLSID -match $CLSID } 
        }
        
        Invoke-Command -ScriptBlock $sb @Params
    }
}


Function Get-WindowsLicenseInfo {
    <#
            .Synopsis
            Get the license status of a Windows computer

            .DESCRIPTION
            Gets the license details via SLMGR.vbs /dlv

            .EXAMPLE
            Get-WindowsLicenseInfo
            Returns the license details of the local computer

            .EXAMPLE
            Get-WindowsLicenseInfo -ComputerName computer01.domain.com
            Returns the license details of the computer
    #>


    Param
    (
        [String] $ComputerName,
        
        [PSCredential] $Credential
    )
    
    Process {
        # Variables
        [ScriptBlock] $sbLicInfo = {
        
            ((cscript $env:windir\System32\slmgr.vbs /dlv | Select-Object -Skip 4) -replace ': ', '=') | 
            ConvertFrom-StringData -ErrorAction SilentlyContinue
        }
        
        If ($ComputerName) {
            If ($Credential) {
                Invoke-Command -ScriptBlock $sbLicInfo -ComputerName $ComputerName -Credential $Credential `
                    -Authentication Kerberos -ErrorAction SilentlyContinue
            }
            Else {
                Invoke-Command -ScriptBlock $sbLicInfo -ComputerName $ComputerName -ErrorAction SilentlyContinue
            }
        }
        Else {
            . $sbLicInfo
        }
    }
}


Function Get-FirewallStatus {
    Param 
    (
        [String]$ComputerName,
		
        [PSCredential]$Credential,
		
        [Switch]$Quiet, 
		
        [Switch]$Debug
    )
	
    $boolShouldContinue = $true
    if ($Debug) { $boolDebug = $true }
	
    # Check if this is to be ran on a remote computer 
    Try {
        If ($ComputerName) {
            $strComputerName = $ComputerName
			
            [ScriptBlock]$sbRemoteCommand = { (netsh adv show current) -Replace '   *', ':' }
			
            $strBaseCommand = "Invoke-Command -ComputerName $strComputerName -Authentication Kerberos -ScriptBlock `$sbRemoteCommand -AsJob -JobName `"remoteFwStatus`""
			
            # check if we're using a credential or windows auth
            If ($Credential) {
                $strRemoteCommand = $strBaseCommand + " -Credential `$Credential"
				
                If ($boolDebug) { Write-Host -f Red "$strRemoteCommand"; Read-Host "Press Enter to continue." };
				
            } 
            Else {
                $strRemoteCommand = $strBaseCommand
				
                If ($boolDebug) { Write-Host -f Red "$strRemoteCommand"; Read-Host "Press Enter to continue." }
            }
			
            Invoke-Expression $strRemoteCommand | Out-Null
            Wait-Job remoteFwStatus | Out-Null # Wait on the job to finish
            $objRawOutput = Receive-Job remoteFwStatus # Receive the output from the job 
            Remove-Job remoteFwStatus | Out-Null # Clean up the job that was created
			
        } 
        Else {
		
            $strComputerName = $env:computername
            $objRawOutput = (netsh adv show current) -Replace '   *', ':'
        }
		
    } 
    Catch {
        Write-Host -f Red "Something went wrong while connecting to $strComputerName"
        $boolShouldContinue = $false
    }
	
    If ($boolShouldContinue) {
        # Set the object for the active firewall profile
        $objActiveFirewallProfile = @()
		
        # Get the active policy name 
        $strActiveProfile = $objRawOutput[1].Split(' ')[0].Trim()
		
        # loop thru to make objects... dirty, I know...
        Foreach ($field in $objRawOutput) { 
            If ($field -ne '') {
                $strSplitField = $field.Split(':')
				
                # build the objects based on matches
                If ($strSplitField[0] -eq 'State') { $strStatusValue = $strSplitField[1] }
                If ($strSplitField[0] -eq 'LogAllowedConnections') { $strLogSuccess = $strSplitField[1] }
                If ($strSplitField[0] -eq 'LogDroppedConnections') { $strLogFailed = $strSplitField[1] }
                If ($strSplitField[0] -eq 'FileName') { $strFilePath = $strSplitField[1] }
                If ($strSplitField[0] -eq 'MaxFileSize') { [int]$intFileSize = $strSplitField[1] }
            }
        }
		
        # build an object to return
        $item = New-Object PSObject

        $item | Add-Member -type NoteProperty -Name 'ComputerName' -Value "$strComputerName"
        $item | Add-Member -type NoteProperty -Name 'ActiveProfile' -Value "$strActiveProfile"
        $item | Add-Member -type NoteProperty -Name 'State' -Value "$strStatusValue"
        $item | Add-Member -type NoteProperty -Name 'LogAllowedConnections' -Value "$strLogSuccess"
        $item | Add-Member -type NoteProperty -Name 'LogDroppedConnections' -Value "$strLogFailed"
        $item | Add-Member -type NoteProperty -Name 'MaxFileSize' -Value $intFileSize
        $item | Add-Member -type NoteProperty -Name 'FileName' -Value "$strFilePath"
		
        # Put all tha things in tha thing... 
        $objActiveFirewallProfile = $item
		
        If ($Quiet) {
            If ($objActiveFirewallProfile.State -eq 'ON') {
                $true
            } 
            Else {
                $false
            }
        } 
        Else {
            $objActiveFirewallProfile
        }
    }
}


#endregion


#region UNDER_CONSTRUCTION


<#
        Function Private:Dev_Invoke-Elevate
        {

        # TODO: 
        # - have output return to the main screen
        # - launch the elevated process with wscript to avoid UAC
        # - work out an elevated prompt, and all commands ran will use elevation until...
    
        [CmdLetBinding()]
        [CmdletBinding(DefaultParameterSetName='Command')]
        Param
        (
        # ScriptBlock: Negates the need for Command
        [Parameter(Mandatory=$false,ParameterSetName="Command")]
        [Parameter(Mandatory=$true, Position=0,ParameterSetName='ScriptBlock',                
        HelpMessage='Scriptblock of commands to be executed')]
        [ScriptBlock] $ScriptBlock,
        
        # Command: Negates the need for ScriptBlock
        [Parameter(Mandatory=$false, ParameterSetName='ScriptBlock')]
        [Parameter(Mandatory=$true, Position=0, ParameterSetName='Command',
        HelpMessage='Commands to be executed')]
        [String] $Command,
        
        [Switch] $NoProfile,
        
        [Switch] $Persist
        )
    
        Begin
        {
        # Invoke-VariableBaseLine
        
        [Bool] $boolDebug = $PSBoundParameters.Debug.IsPresent
        }
    
        Process 
        {
    
        [String] $strCommand = "& { $ScriptBlock }"
 
        IF ($Command)
        {
        [String] $strCommand = $Command
        }
        
        [String] $strEncodedCommand = [Convert]::ToBase64String($([System.Text.Encoding]::Unicode.GetBytes($strCommand)))
        [String] $strArguments = "-Exec ByPass -EncodedCommand $strEncodedCommand"
        
        IF ($NoProfile)
        {
        $strArguments =+ ' -Nop'
        }
        
        IF ($Persist)
        {
        $strArguments += ' -NoExit'
        }
    
        Start-Process PowerShell -Verb runas -ArgumentList $strArguments
        }
    
        End
        {
        # Invoke-VariableBaseLine -Clean
        }
        }
#>


#endregion
