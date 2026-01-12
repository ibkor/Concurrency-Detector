 # This project is licensed under the MIT License - see the LICENSE file for details.
$ExportPath = "C:\csv"   #change if needed

#Connect to VBR
$creds = Get-Credential
Connect-VBRServer -Credential $creds -Server "Your VBR Server"

# Rescan all the host when needed
function Get-UserResponse {
    $validResponses = @('y', 'n')
    $response = ''

    # Keep asking for input until a valid response is received
    while ($true) {
        $promptMessage = "Would you like to rescan all hosts to ensure the data is up-to-date? Please enter 'y' for yes or 'n' for no:"
        $response = Read-Host -Prompt $promptMessage

        if ($validResponses -contains $response) {
            return $response
        } else {
            Write-Host "Invalid input. Please enter 'y' or 'n'."
        }
    }
}

$userResponse = Get-UserResponse

# Check the user's response
if ($userResponse -eq 'y') {
    Write-Host "Rescanning all hosts... Please wait."
    Rescan-VBREntity -AllHosts -Wait
    Write-Host "Rescan complete. Proceeding with data retrieval."
} else {
    Write-Host "Skipping rescan. Using existing data."
}

$BackupServerInfo = Get-VBRBackupServerInfo

#Get all VMware proxies
$VMwareProxies = Get-VBRViProxy

# Get all CDP proxies
$CDPProxies = Get-VBRCDPProxy

# Get all VBR Repositories
$VBRRepositories = Get-VBRBackupRepository

$BackupServerName = [System.Net.Dns]::GetHostByName(($env:computerName)).HostName

#Get All GP Proxies
$GPProxies = Get-VBRNASProxyServer

$ProxyData = @()
$CDPProxyData = @()
$GWData = @()
$RepoData = @()
$GPProxyData = @()
$RequirementsComparison = @()
$hostRoles = @{}

#Get SQL Server Host
function Get-SqlSName {
    # Define registry paths and keys
    $basePath = "HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication"
    $databaseConfigurationPath = "$basePath\DatabaseConfigurations"
    $sqlActiveConfigurationKey = "SqlActiveConfiguration"
    $postgreSqlPath = "$databaseConfigurationPath\PostgreSql"
    $msSqlPath = "$databaseConfigurationPath\MsSql"
    $sqlServerNameKey = "SqlServerName"
    $sqlHostNameKey = "SqlHostName"
    $SQLSName = $null

    try {
        $SQLSName = (Get-ItemProperty -Path $basePath -Name $sqlServerNameKey -ErrorAction Stop).SqlServerName
    } catch {
        try {
            $sqlActiveConfig = Get-ItemProperty -Path $databaseConfigurationPath -Name $sqlActiveConfigurationKey -ErrorAction Stop
            $activeConfigValue = $sqlActiveConfig.$sqlActiveConfigurationKey

            if ($activeConfigValue -eq "PostgreSql") {
                $SQLSName = (Get-ItemProperty -Path $postgreSqlPath -Name $sqlHostNameKey -ErrorAction Stop).SqlHostName
            } else {
                $SQLSName = (Get-ItemProperty -Path $msSqlPath -Name $sqlServerNameKey -ErrorAction Stop).SqlServerName
            }
        } catch {
            Write-Error "Unable to retrieve SQL Server name from registry."
        }
    }

    If ($SQLSName -eq "localhost") {
        $SQLSName = $BackupServerName
    }
return $SQLSName
}

function ConverttoGB ($inBytes) {
    $inGB = [math]::Floor($inBytes / 1GB)
    return $inGB
}

# Function to ensure values are non-negative
function EnsureNonNegative {
    param (
        [int]$Value
    )
    
    if ($Value -lt 0) {
        return 0
    } else {
        return $Value
    }
}

#Gather GP Proxy Data
foreach ($GPProxy in $GPProxies) {
    $NrofGPProxyTasks = $GPProxy.ConcurrentTaskNumber
    $Serv = Get-VBRServer -Name $GPProxy.Server.Name
    $GPProxyCores = $Serv.GetPhysicalHost().HardwareInfo.CoresCount
    $GPProxyRAM = ConverttoGB($Serv.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
    
    $GPProxyDetails = [PSCustomObject]@{
        "GP Proxy Name"         = $GPProxy.Server.Name
        "GP Proxy Server"       = $GPProxy.Server.Name
        "GP Proxy Cores"        = $GPProxyCores
        "GP Proxy RAM (GB)"     = $GPProxyRAM        
        "GP Concurrent Tasks"   = $NrofGPProxyTasks
    }                        

    $GPProxyData += $GPProxyDetails

    # Track host roles with Proxy.Name
    if (-not $hostRoles.ContainsKey($GPProxy.Server.Name)) {
        $hostRoles[$GPProxy.Server.Name] = [ordered]@{
            "Roles" = @("GPProxy")
            "Names" = @($GPProxy.Server.Name) 
            "TotalTasks" = 0
            "Cores" = $GPProxyCores
            "RAM" = $GPProxyRAM
            "Task" = $NrofGPProxyTasks
            "TotalGPProxyTasks" = 0
        }
    } else {
        $hostRoles[$GPProxy.Server.Name].Roles += "GPProxy"
        $hostRoles[$GPProxy.Server.Name].Names += $GPProxy.Server.Name
    }
    $hostRoles[$GPProxy.Server.Name].TotalGPProxyTasks += $NrofGPProxyTasks
    $hostRoles[$GPProxy.Server.Name].TotalTasks += $NrofGPProxyTasks
}

# Gather ViProxy Data
foreach ($Proxy in $VMwareProxies) {
    $NrofProxyTasks = $Proxy.MaxTasksCount
    $ProxyCores = $Proxy.GetPhysicalHost().HardwareInfo.CoresCount
    $ProxyRAM = ConverttoGB($Proxy.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
    
    $ProxyDetails = [PSCustomObject]@{
        "Proxy Name"         = $Proxy.Name
        "Proxy Server"       = $Proxy.Host.Name
        "Proxy Cores"        = $ProxyCores
        "Proxy RAM (GB)"     = $ProxyRAM        
        "Concurrent Tasks"   = $NrofProxyTasks
    }                        

    $ProxyData += $ProxyDetails

    # Track host roles with Proxy.Name
    if (-not $hostRoles.ContainsKey($Proxy.Host.Name)) {
        $hostRoles[$Proxy.Host.Name] = [ordered]@{
            "Roles" = @("Proxy")
            "Names" = @($Proxy.Name) 
            "TotalTasks" = 0
            "Cores" = $ProxyCores
            "RAM" = $ProxyRAM
            "TotalViProxyTasks" = 0
        }
    } else {
        $hostRoles[$Proxy.Host.Name].Roles += "Proxy"
        $hostRoles[$Proxy.Host.Name].Names += $Proxy.Name
    }
    $hostRoles[$Proxy.Host.Name].TotalViProxyTasks += $NrofProxyTasks
    $hostRoles[$Proxy.Host.Name].TotalTasks += $NrofProxyTasks
}

# Gather CDP Proxy Data
foreach ($CDPProxy in $CDPProxies) {
    $Serv = Get-VBRServer -Name $CDPProxy.Name
    $CDPProxyCores = $Serv.GetPhysicalHost().HardwareInfo.CoresCount
    $CDPProxyRAM = ConverttoGB($Serv.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
    
    $CDPProxyDetails = [PSCustomObject]@{
        "CDP Proxy Name"     = $CDPProxy.Name        
        "CDP Proxy Cores"    = $CDPProxyCores
        "CDP Proxy RAM (GB)" = $CDPProxyRAM
    }

    $CDPProxyData += $CDPProxyDetails

    # Track host roles with CDPProxy.Name
    if (-not $hostRoles.ContainsKey($CDPProxy.Name)) {
        $hostRoles[$CDPProxy.Name] = [ordered]@{
            "Roles" = @("CDPProxy")
            "Names" = @($CDPProxy.Name)
            "TotalTasks" = 0
            "Cores" = $CDPProxyCores
            "RAM" = $CDPProxyRAM
        }
    } else {
        $hostRoles[$CDPProxy.Name].Roles += "CDPProxy"
        $hostRoles[$CDPProxy.Name].Names += $CDPProxy.Name 
    }
}

# Gather Repository and Gateway Data
foreach ($Repository in $VBRRepositories) {
    $NrofRepositoryTasks = $Repository.Options.MaxTaskCount
    $gatewayServers = $Repository.GetActualGateways()

    if ($gatewayServers.Count -gt 0) {
        foreach ($gatewayServer in $gatewayServers) {
            $Server = Get-VBRServer -Name $gatewayServer.Name
            $GWCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
            $GWRAM = ConverttoGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
            
            $RepositoryDetails = [PSCustomObject]@{
                "Repository Name"   = $Repository.Name
                "Gateway Server"    = $gatewayServer.Name
                "Gateway Cores"     = $GWCores
                "Gateway RAM (GB)"  = $GWRAM        
                "Concurrent Tasks"  = $NrofRepositoryTasks
            }                        
            $GWData += $RepositoryDetails

            # Track host roles
            if (-not $hostRoles.ContainsKey($gatewayServer.Name)) {
                $hostRoles[$gatewayServer.Name] = [ordered]@{
                    "Roles" = @("Gateway")
                    "Names" = @($gatewayServer.Name) 
                    "TotalTasks" = 0
                    "Cores" = $GWCores
                    "RAM" = $GWRAM
                    "TotalGWTasks" = 0
                }
            } else {
                $hostRoles[$gatewayServer.Name].Roles += "Gateway"
                $hostRoles[$gatewayServer.Name].Names += $Repository.Name
            }
            $hostRoles[$gatewayServer.Name].TotalGWTasks += $NrofRepositoryTasks
            $hostRoles[$gatewayServer.Name].TotalTasks += $NrofRepositoryTasks

        }
    } else {
        # Handle the repository host
        $Server = Get-VBRServer -Name $Repository.Host.Name
        $RepoCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
        $RepoRAM = ConverttoGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

        $RepositoryDetails = [PSCustomObject]@{
            "Repository Name"   = $Repository.Name
            "Repository Server" = $Repository.Host.Name
            "Repository Cores"  = $RepoCores
            "Repository RAM (GB)" = $RepoRAM        
            "Concurrent Tasks"   = $NrofRepositoryTasks
        }            
        $RepoData += $RepositoryDetails

        # Track host roles
        if (-not $hostRoles.ContainsKey($Repository.Host.Name)) {
            $hostRoles[$Repository.Host.Name] = [ordered]@{
                "Roles" = @("Repository")
                "Names" = @($Repository.Name)
                "TotalTasks" = 0
                "Cores" = $RepoCores
                "RAM" = $RepoRAM
                "TotalRepoTasks" = 0
            }
        } else {
            $hostRoles[$Repository.Host.Name].Roles += "Repository"
            $hostRoles[$Repository.Host.Name].Names += $Repository.Name
        }
        $hostRoles[$Repository.Host.Name].TotalRepoTasks += $NrofRepositoryTasks
        $hostRoles[$Repository.Host.Name].TotalTasks += $NrofRepositoryTasks

    }
}

$hostRoles[$BackupServerName].Roles += ("BackupServer" -join ', ')

$SQLServer = Get-SqlSName
try {
    $hostRoles[$SQLServer].Roles += ("SQLServer" -join ', ')
} catch {
    Write-Host "SQLServer is $SQLServer."
    }


# Calculate requirements based on aggregated resources for multi-role servers
foreach ($server in $hostRoles.GetEnumerator()) {
    $SuggestedTasksByCores = 0 
    $SuggestedTasksByRAM = 0
    $serverName = $server.Key
    $CPUTasks = $server.Value.TotalRepoTasks + $server.Value.TotalGWTasks + $server.Value.TotalViProxyTasks
    $MemTasks = $server.Value.TotalRepoTasks + $server.Value.TotalGWTasks
    $coresAvailable = $server.Value.Cores
    $ramAvailable = $server.Value.RAM
    $totalTasks = $server.Value.TotalTasks
    $SuggestionCores = $coresAvailable
    $SuggestionRAM = $ramAvailable

    # Calculate requirements
    $RequiredCores = [Math]::Ceiling($CPUTasks / 2) # 2 tasks per CPU core
    $RequiredRAM = $MemTasks # 1 GB RAM per task

    if($server.Value.Roles -contains "GPProxy") {
        $RequiredCores += 2   #CPU core requirement for GP Proxy
        $RequiredRAM += 2 + ($server.Value.TotalGPProxyTasks)*4
        $SuggestionCores += -2
        $SuggestionRAM += -2 - ($server.Value.TotalGPProxyTasks)*4
    }
 
    if($server.Value.Roles -contains "CDPProxy") {
        $RequiredCores += 4  #CPU core requirement for CDP Proxy added
        $RequiredRAM += 8    #RAM requirement for CDP Proxy added
        $SuggestionCores += -4
        $SuggestionRAM += -8
    }
   
    if ($serverName -contains $BackupServerName -and $BackupServerInfo.Build.Major -eq "13") {
        $RequiredCores += 8  #CPU core requirement for Backup Server added
        $RequiredRAM += 16    #RAM requirement for Backup Server added
        $SuggestionCores += -8
        $SuggestionRAM += -16
    } elseif ($serverName -contains $BackupServerName -and $BackupServerInfo.Build.Major -lt "13") {
        $RequiredCores += 4  #CPU core requirement for Backup Server added
        $RequiredRAM += 8    #RAM requirement for Backup Server added
        $SuggestionCores += -4
        $SuggestionRAM += -8
    }

    if ($SQLServer -eq $serverName) {
        $RequiredCores += 1  #min CPU core requirement for SQL Server added
        $RequiredRAM += 1    #min RAM requirement for SQL Server added
        $SuggestionCores += -1
        $SuggestionRAM += -1
    }

    $SuggestedTasksByCores += $SuggestionCores*2
    $SuggestedTasksByRAM += $SuggestionRAM  

    $NonNegativeCores = EnsureNonNegative($SuggestedTasksByCores)
    $NonNegativeRAM = EnsureNonNegative($SuggestedTasksByRAM)

    # Calculate the max suggested tasks using non-negative values
    $MaxSuggestedTasks = [Math]::Min($NonNegativeCores, $NonNegativeRAM)

    $RequirementComparison = [PSCustomObject]@{
        "Server"          = $serverName
        "Type"            = ($server.Value.Roles -join '; ')
        "Required Cores"  = $RequiredCores
        "Available Cores" = $coresAvailable
        "Required RAM (GB)" = $RequiredRAM
        "Available RAM (GB)" = $ramAvailable
        "Concurrent Tasks" = $totalTasks
        "Suggested Tasks"  = $MaxSuggestedTasks
        "Names"           = ($server.Value.Names -join '; ')
    }
    $RequirementsComparison += $RequirementComparison
}

# Output summary of Repositories, Proxies, and CDP Proxies found
Write-Host "$($RepoData.Count) Repositories Found:"
$RepoData | Format-Table

Write-Host "$($GWData.Count) Gateways found:"
$GWData | Format-Table 

Write-Host "$($ProxyData.Count) Proxies found:"
$ProxyData | Format-Table 

Write-Host "$($CDPProxyData.Count) CDP Proxies found:"
$CDPProxyData | Format-Table 

Write-Host "$($GPProxyData.Count) GP Proxies found:"
$GPProxyData | Format-Table 

# Detect and mention which hosts are used for multiple roles
$multiRoleServers = $hostRoles.GetEnumerator() | Where-Object { $_.Value.Roles.Count -gt 1 }

if ($multiRoleServers) {
    $multiRoleServers | ForEach-Object {
        Write-Host "$($_.Key) has roles: $($_.Value.Roles -join '; ') - Names: $($_.Value.Names -join '; ')"
    }
} else {
    Write-Host "No servers are being used for multiple roles."
}

# Output the requirements comparison
Write-Host "Requirements Comparison:"

# Separate the outputs into optimized, underconfigured, and suboptimal configurations based on the comparison
$OptimizedConfiguration = @()
$SuboptimalConfiguration = @()
$UnderconfiguredConfiguration = @()

foreach ($req in $RequirementsComparison) {

    if ($req."Concurrent Tasks" -le $req."Suggested Tasks" -or ($req.'Required RAM (GB)' -le $req.'Available RAM (GB)' -and $req.'Required Cores' -le $req.'Available Cores')) {
        $OptimizedConfiguration += $req
    } else {
        $SuboptimalConfiguration += $req
    }
}

# Display the Optimized Configuration
if ($OptimizedConfiguration.Count -gt 0) {
    Write-Host "Optimized Configuration:"
    $OptimizedConfiguration | Format-Table 
} else {
    Write-Host "No servers found with optimized configuration."
}


# Display the Suboptimal Configuration
if ($SuboptimalConfiguration.Count -gt 0) {
    Write-Host "Suboptimal Configuration:"
    $SuboptimalConfiguration | Format-Table 
} else {
    Write-Host "No servers found with suboptimal configuration."
}

# Exporting the data to CSV files

$RepoData | Export-Csv -Path "$ExportPath\Repositories.csv" -NoTypeInformation
$GWData | Export-Csv -Path "$ExportPath\Gateways.csv" -NoTypeInformation
$ProxyData | Export-Csv -Path "$ExportPath\Proxies.csv" -NoTypeInformation
$CDPProxyData | Export-Csv -Path "$ExportPath\CDPProxies.csv" -NoTypeInformation
$RequirementsComparison | Export-Csv -Path "$ExportPath\RequirementsComparison.csv" -NoTypeInformation

# Exporting the separated configurations to CSV files for optimized, underconfigured, and suboptimal
$OptimizedConfiguration | Export-Csv -Path "$ExportPath\OptimizedConfiguration.csv" -NoTypeInformation
$SuboptimalConfiguration | Export-Csv -Path "$ExportPath\SuboptimalConfiguration.csv" -NoTypeInformation

Write-Host "Data exported to CSV files successfully."  

