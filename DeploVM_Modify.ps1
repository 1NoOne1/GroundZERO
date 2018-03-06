<#
.SYNOPSIS
Deploy Multiple VMs to vCenter

.DESCRIPTION
VMs are deployed asynchronously based on a pre-configured csv file (DeployVM.csv)
Designed to run from Powershell ISE

.PARAMETER deployvm
Path to DeployVM.csv file with new VM info

.PARAMETER credentials
path vCenter.csv file with vCenter Server FQDN or IP along with the credentials

.PARAMETER auto
Will allow script to run with no review or confirmation

.PARAMETER createdeployvmcsv
Generates a blank csv file - DeployVM.csv

.EXAMPLE
.\DeployVM.ps1
Runs DeployVM

.\DeployVM.ps1 -deployvm .\DeployVM.csv -credentials .\vCenter.csv
Runs DeployVM using new VMs info and vCenter Information.

.EXAMPLE
.\DeployVM.ps1 -createdeployvmcsv
Creates a new/blank DeployVM.csv file in same directory as script as a reference template.

REQUIREMENTS
PowerShell v3 or greater
vCenter (tested on 5.1/5.5)
PowerCLI 5.5 R2 or later
CSV File - VM info with the following headers
    NewVM, Name, Boot, OSType, Template, Folder, ResourcePool, CPU, RAM, Disk2, Disk3, Disk4, SDRS, Datastore, DiskStorageFormat, NetType, NICcount, Network1, DHCP1, IPAddress1, SubnetMask1, Gateway1, Network2, DHCP2, IPAddress2, SubnetMask2, Gateway2, Network3, DHCP3, IPAddress3, SubnetMask3, Gateway3, pDNS, sDNS, Notes, Domain, OU
    Must be named DeployVM.csv
    Can be created with -createdeployvmcsv switch
CSV Field Definitions
  NewVM - Name of VM
	Name - Name of guest OS VM
	Boot - Determines whether or not to boot the VM - Must be 'true' or 'false'
	OSType - Must be 'Linux' [took out windows support]
	Template - Name of existing template to clone
	Folder - Folder in which to place VM in vCenter (optional)
	ResourcePool - VM placement - can be a reasource pool, host or a cluster
	CPU - Number of vCPU
	RAM - Amount of RAM in GB
	Disk2 - Size of additional disk to add (GB)(optional)
	Disk3 - Size of additional disk to add (GB)(optional)
	Disk4 - Size of additional disk to add (GB)(optional)
    SDRS - Mark to use a SDRS or not - Must be 'true' or 'false'
	Datastore - Datastore placement - Can be a datastore or datastore cluster
	DiskStorageFormat - Disk storage format - Must be 'Thin', 'Thick' or 'EagerZeroedThick' - Only funcional when SDRS = true
	NetType - vSwitch type - Must be 'vSS' or 'vDS'
	Network - Network/Port Group to connect NIC
	DHCP - Use DHCP - Must be 'true' or 'false'
	IPAddress - IP Address for NIC
	SubnetMask - Subnet Mask for NIC
	Gateway - Gateway for NIC
	pDNS - Primary DNS must be populated
	sDNS - Secondary NIC must be populated
	Notes - Description applied to the vCenter Notes field on VM
    Domain - DNS Domain must be populated
    OU - OU to create new computer accounts, must be the distinguished name eg "OU=TestOU1,OU=Servers,DC=my-homelab,DC=local"

CREDITS
Handling New-VM Async - LucD - @LucD22
http://www.lucd.info/2010/02/21/about-async-tasks-the-get-task-cmdlet-and-a-hash-table/
http://blog.smasterson.com/2014/05/21/deploying-multiple-vms-via-powercli-updated-v1-2/
http://blogs.vmware.com/PowerCLI/2014/05/working-customization-specifications-powercli-part-1.html
http://blogs.vmware.com/PowerCLI/2014/06/working-customization-specifications-powercli-part-2.html
http://blogs.vmware.com/PowerCLI/2014/06/working-customization-specifications-powercli-part-3.html

#>

#requires -Version 3

#--------------------------------------------------------------------
# Parameters
<# param (
    [parameter(Mandatory=$false)]
    [string]$deployvm,
    [parameter(Mandatory=$false)]
    [string]$credentials,
    [parameter(Mandatory=$false)]
    [switch]$auto,
    [parameter(Mandatory=$false)]
    [switch]$createdeployvmcsv
    )

#--------------------------------------------------------------------
# User Defined Variables

#--------------------------------------------------------------------
# Static Variables

$scriptName = "DeployVM"
$scriptVer = "1.6"
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$starttime = Get-Date -uformat "%m-%d-%Y %I:%M:%S"
$logDir = $scriptDir + "\Logs\"
$logfile = $logDir + $scriptName + "_" + (Get-Date -uformat %m-%d-%Y_%I-%M-%S) + "_" + $env:username + ".txt"
$deployedDir = $scriptDir + "\Deployed\"
$deployedFile = $deployedDir + "DeployVM_" + (Get-Date -uformat %m-%d-%Y_%I-%M-%S) + "_" + $env:username  + ".csv"
$exportpath = $scriptDir + "\DeployVM.csv"
$headers = "" | Select-Object NewVM, Name, Boot, OSType, Template, Folder, ResourcePool, CPU, RAM, Disk2, Disk3, Disk4, SDRS, Datastore, DiskStorageFormat, NetType, NICcount, Network1, DHCP1, IPAddress1, SubnetMask1, Gateway1, Network2, DHCP2, IPAddress2, SubnetMask2, Gateway2, Network3, DHCP3, IPAddress3, SubnetMask3, Gateway3, pDNS, sDNS, Notes, Domain, OU
$taskTab = @{} 
$deplyVM_Collector = @()

# Get Start Time
$startDTM = (Get-Date)

#--------------------------------------------------------------------
# Load Snap-ins

# Add VMware snap-in if required
Get-Module -Name VMware* -ListAvailable | Import-Module
#If ((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null) {add-pssnapin VMware.VimAutomation.Core} {add-pssnapin ActiveDirectory}

#--------------------------------------------------------------------
# Functions

Function Out-Log {
    Param(
        [Parameter(Mandatory=$true)][string]$LineValue,
        [Parameter(Mandatory=$false)][string]$fcolor = "White"
    )

    Add-Content -Path $logfile -Value $LineValue
    Write-Host $LineValue -ForegroundColor $fcolor
}

Function Read-OpenFileDialog([string]$WindowTitle, [string]$InitialDirectory, [string]$Filter = "CSV (*.csv)| *.csv", [switch]$AllowMultiSelect)
{
    Add-Type -AssemblyName System.Windows.Forms
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = $WindowTitle
    if (![string]::IsNullOrWhiteSpace($InitialDirectory)) { $openFileDialog.InitialDirectory = $InitialDirectory }
    $openFileDialog.Filter = $Filter
    if ($AllowMultiSelect) { $openFileDialog.MultiSelect = $true }
    $openFileDialog.ShowHelp = $true    # Without this line the ShowDialog() function may hang depending on system configuration and running from console vs. ISE.
    $openFileDialog.ShowDialog() > $null
    if ($AllowMultiSelect) { return $openFileDialog.Filenames } else { return $openFileDialog.Filename }
}


#--------------------------------------------------------------------
# Main Procedures

# Start Logging
#Clear-Host
If (!(Test-Path $logDir)) {New-Item -ItemType directory -Path $logDir | Out-Null}
Out-Log "**************************************************************************************"
Out-Log "$scriptName`tVer:$scriptVer`t`t`t`tStart Time:`t$starttime"
Out-Log "**************************************************************************************`n"

# If requested, create DeployVM.csv and exit
If ($createdeployvmcsv) {
    If (Test-Path $exportpath) {
        Out-Log "`n$exportpath Already Exists!`n" "Red"
        Exit
    } Else {
        Out-Log "`nCreating $exportpath`n" "Yellow"
        $headers | Export-Csv $exportpath -NoTypeInformation
		Out-Log "Done!`n"
        Exit
    }
}

# Ensure PowerCLI is at least version 5.5 R2 (Build 1649237)
If ((Get-PowerCLIVersion).Build -lt 1649237) {
    Out-Log "Error: DeployVM script requires PowerCLI version 5.5 R2 (Build 1649237) or later" "Red"
	Out-Log "PowerCLI Version Detected: $((Get-PowerCLIVersion).UserFriendlyVersion)" "Red"
    Out-Log "Exiting...`n`n" "Red"
    Exit
}

# Test to ensure DeployVM csv file is available
If ($deployvm -eq "" -or !(Test-Path $deployvm)) {
    Out-Log "Path to DeployVM.csv not specified...prompting`n" "Yellow"
    $deployvm = Read-OpenFileDialog "Locate DeployVM.csv"
}

If ($deployvm -eq "" -or !(Test-Path $deployvm)) {
    Out-Log "`nStill can't find it...I give up" "Red"
    Out-Log "Exiting..." "Red"
    Exit
}

# Test to ensure vCenter credentials csv file is available
If ($credentials -eq "" -or !(Test-Path $credentials)) {
    Out-Log "Path to vCenter.csv not specified...prompting`n" "Yellow"
    $credentials = Read-OpenFileDialog "Locate vCenter.csv"
}


Out-Log "`r`Using $deployvm`n" "Yellow"
# Make copy of DeployVM.csv
If (!(Test-Path $deployedDir)) {New-Item -ItemType directory -Path $deployedDir | Out-Null}
Copy-Item $deployvm -Destination $deployedFile | Out-Null

# Import VMs from csv
$newVMs = Import-Csv $deployvm
$ColumnsCsv_newVMs = $newVMs | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
$newVMs = $newVMs | Where {$_.Name -ne ""}
[INT]$totalVMs = @($newVMs).count
Out-Log "`r`n[ New VMs to create: $totalVMs ] ***************************************************************************************************************************************" "Yellow"

# Import vCenter information from csv
$vCenter = Import-Csv $credentials

# Connect to vCenter server

If (!($($vCenter.vCenter))) 
{
    Out-Log "`r`n`r***************************************************************************************************************************************************************" "Red"
		Out-Log "`r`n`r`n The Name of the vCenter is empty, Please check your CSV File..." "Red"
    Out-Log "Exiting...`r`n`r`n" "Red"
    Exit
}
Else
{
   $vc_credentials = Get-Credential
   Try {
        Out-Log "`r`n[ Connecting to vCenter: $($vCenter.vCenter) ] ************************************************************************************************************" "White"
        #Connect-VIServer -Server $($vCenter.vCenter) -User $($vCenter.User) -Password $($vCenter.Pass) -WarningAction SilentlyContinue | Out-Null
		Connect-VIServer -Server $($vCenter.vCenter) -Credential $vc_credentials -ErrorAction Stop | Out-Null
    } 
    Catch [Exception]{
		$status = 400
		$exception = $_.Exception
        Out-Log "`r`n`r`n[ Unable to connect to vCenter: $($vCenter.vCenter) : [$status] : [$exception.message]] *****************************************************************************************************" "Red"
        Out-Log "Exiting...`r`n`r`n" "Red"
        Exit
	}
}


<#
ForEach($vm in $newVMs){

    Out-Log "`nPrinting all the values in given vm csv file:::" "Green"
    Out-Log "`r`nVm Guest to add is : $vm " "Yellow"
}

ForEach($vcenter in $vCenter){

    Out-Log "`nPrinting all the values in given vCenter csv file:::" "Green"
    Out-Log "`r`nvCenter Details are : $vcenter " "Yellow"

}
#exit
#>

# Start provisioning VMs
<# $v = 0
Out-Log "`r`n[ Deploying VMs to vCenter: $($vCenter.vCenter) ] ********************************************************************************************************" "White"
Foreach ($VM in $newVMs) {
    $Error.Clear()
    $vmName = $VM.Name
    $v++
	$deplyVM_Collector+=$vmName
    $vmStatus = "[{0} of {1}] {2}" -f $v, $newVMs.count, $vmName
    Write-Progress -Activity "Deploying VMs" -Status $vmStatus -PercentComplete (100*$v/($newVMs.count + 1))

	# Create VM depending on the parameter SDRS true or false
	Out-Log "`r`nDeploying VM: [ $vmName ]"

	If ($VM.SDRS -match "TRUE") 
    {
		Out-Log "SDRS Cluster disk on: [ $vmName ] - removing DiskStorageFormat parameter " "Yellow"
			
		$taskTab[(New-VM -Name $VM.NewVM -ResourcePool $VM.ResourcePool -Location $VM.Folder -Datastore $VM.Datastore `
	    -Notes $VM.Notes -Template $VM.Template -RunAsync).Id] = $VM.Name
	} 
	Else 
    {
		Out-Log "NON SDRS Cluster disk on: [ $vmName ] - using DiskStorageFormat parameter " "Yellow"
		$taskTab[(New-VM -Name $VM.NewVM -ResourcePool $VM.ResourcePool -Location $VM.Folder -Datastore $VM.Datastore -DiskStorageFormat $VM.DiskStorageFormat -Notes $VM.Notes -Template $VM.Template -RunAsync -ErrorAction SilentlyContinue).Id] = $VM.Name
	}
	
	# Log errors
	If ($Error.Count -ne 0) 
    {
		If ($Error.Count -eq 1 -and $Error.Exception -match "'Location' expects a single value") 
        {
			$vmLocation = $VM.Folder
			Out-Log "`r`n`r***************************************************************************************************************************************************************" "Red"
			Out-Log "`r`n[Unable to place [ $vmName ] in desired location, looks like multiple [ $vmLocation ] folders exist, Please check root folder in vCenter]" "Red"
		} 
        Else 
        {
			Out-Log "`r`n[ $vmName ] failed to deploy in : [$($vCenter.vCenter)]" "Red"
			Foreach ($err in $Error) {
				Out-Log "$err" "Red"
			}
			$failDeploy += @($vmName)
		}
	}

} #> #>

$deplyVM_Collector = @("rco1evn0424","rco1evn0425","rco1evn0426","rco1evn0427","rco1evn0428","rco1evn0429","rco1evn0430","rco1evn0431","rco1evn0432","rco1evn0433","rco1evn0434")
$failDeploy = @("rco1evn0427","rco1evn0431","rco1evn0429")



#delete failed vms from total vm as we don't have to reconfigure the VMs that are failed to deploy 
$VMs_2_Check = $deplyVM_Collector | where {$failDeploy -notcontains $_}

Write-Host "deplyVM_Collector : $deplyVM_Collector"
Write-Host "failDeploy : $failDeploy"
Write-Host "VMs_2_Check : $VMs_2_Check"


$runningTasks_VMs = $VMs_2_Check.Count
$counter = 0
$counter_max = $VMs_2_Check.Count
write-host "counter_max : $counter_max"
while($runningTasks_VMs -ge 0) 
{
	$counter++
	write-host "counter is: $counter"
	$VMs_2_Check_copy = $Null
	$VMs_2_Check_copy = $VMs_2_Check.clone()

	For ($i=0; $i -lt $VMs_2_Check_copy.Length; $i++) 
	{
		$vmstatus = Get-VM $VMs_2_Check_copy[$i]
		#If(($vmstatus -ne $null) -and ($vmstatus.PowerState -eq "PoweredOff"))
		If(($vmstatus -eq $null))
		{
			Write-Host "Echoing the reconfig for $($VMs_2_Check_copy[$i])"
			
			$runningTasks_VMs--
			#here I have to pop-out/remove the VM that I just worked, otherwise when moved into the while loop
			#reconfig works will run on the same VM.
			$VMs_2_Check = $VMs_2_Check | where {$_ -ne $VMs_2_Check_copy[$i]}	
			Write-host "reordered VMs_2_Check: $VMs_2_Check"
		
		}
		Else
		{
			# We are not decreasing the runningTasks_VMs count as well as we not removing the VM from the VMs_2_Check array.
			Write-Host "In Else Block inside For Loop"
			Start-Sleep 0
		}
		
		Write-host "is is $i .........."
		
		If(($i -gt 4) -and ($counter -eq 1))
		{
			$counter = 6
		}
		Else{
			write-host "else"
		}
	}
	write-host " i outside for loop $i"
	write-host " runningTasks_VMs outside for loop $runningTasks_VMs"
	If($counter -gt $counter_max) 
	{
		#we exit the while loop once the counter reached the number of VMs in the input CSV file.
		#If we don't break it will fall into an infinite loop. the check point is total number VMs deployed.
		#Once the count is reached and we are still running, then it's time to check in vCenter.
		
		#We have to send remaining VMs info to failed status to display them in the end.
		$failReconfig+=$VMs_2_Check
		write-host "failReconfig is : $failReconfig"
		Break
	}
}


Exit
   
#Out-Log "`r`n[ TaskTAB contents: ] $taskTab | Out-String ****************************************************************************************************" "Yellow"
Write-Host ($taskTab | Out-String) -ForegroundColor Red
$tasktab_list=($taskTab | Out-String)
Out-Log "`r`n[ Total elements in taskTab :: $tasktab_list] ****************************************************************************************************" "Cyan"
#$tasks = Get-Task -Status "running"
<# While(!(Get-Task | Where { $_.State -eq "Running" }).Count -eq 0)
{
	Start-Sleep 10
} #>

#$tasks| Foreach-Object {
<# Get-Task | % {
	Write-Host "Checking task :: $_" -ForegroundColor Yellow
	Write-Host "$_.Id " -ForegroundColor Yellow
	#Get-VM $_ | get-snapshot | select VM,Name,Description,Created,PowerState | Sort VM,Created
	#Stop-Task -Task $_ -Confirm:$false
	}
Write-Host $tasks -ForegroundColor Red #>
#Exit


Out-Log "`r`n[ All Deployment Tasks for Adding VMs to vCenter Created ] ****************************************************************************************************" "Yellow"
Out-Log "`r`n`n[ Monitoring Task Processing ] ********************************************************************************************************************************" "Yellow" 

#Start-Sleep -Seconds 90
# When finished deploying, reconfigure new VMs to add DNS, NIC Information etc.
$totalTasks = $taskTab.Count
Write-Host "Current Tasks count in vCenter ::  $totalTasks" -ForegroundColor cyan
$c= (Get-Task | Where { $_.State -eq "Running" }).Count
$tasks= Get-Task
Write-Host "count of tasks with running state :  $c" -ForegroundColor cyan
Write-Host "count of tasks with running state :  $tasks" -ForegroundColor cyan
#Exit
$runningTasks = $totalTasks
while($runningTasks -gt 0) {
	$vmStatus = "[{0} of {1}] {2}" -f $runningTasks, $totalTasks, "Tasks Remaining"
	Write-Progress -Activity "Monitoring Task Processing" -Status $vmStatus -PercentComplete (100*($totalTasks-$runningTasks)/$totalTasks)
	$tasks = Get-Task
	Write-Host "Current Tasks count in vCenter ::  $($tasks.Count)" -ForegroundColor Red
	Out-Log "`r`n[ RunningTasks Count: $runningTasks] ****************************************************************************************************" "Cyan"
	Write-Host "Getting the tasks here" -ForegroundColor "Yellow"
	#Out-File -FilePath C:\PowerCLi\tasks1.txt -InputObject $tasks
	Get-Task | % {
		If($taskTab.ContainsKey($_.Id) -and $_.State -eq "Success")
		{
			Write-Host ($taskTab | Out-String) -ForegroundColor Yellow
			Write-Host $_.Id -ForegroundColor Cyan
			#Deployment completed
			#$Error.Clear()
			$vmName = $taskTab[$_.Id]
		
			Out-Log "`r`n[ Reconfiguring : $vmName ] **********************************************************************************************************************" "White"
			$VM = Get-VM $vmName
			$VMconfig = $newVMs | Where {$_.Name -eq $vmName}
		
			$ColumnsCsv_newVMs = $newVMs | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
		
			# Set CPU and RAM
			Out-Log "`r`n[ Setting vCPU(s) and RAM on: $vmName ] *********************************************************************************************" "White"
			Out-Log "`nvCPU(s): [$($VMconfig.CPU)]; RAM: [$($VMconfig.RAM)]" "Yellow"
			$VM | Set-VM -NumCpu $VMconfig.CPU -MemoryGB $VMconfig.RAM -Confirm:$false | Out-Null

			# Set port group on virtual adapter
			Out-Log "`r`n[ Setting Port Group on: $vmName ] **************************************************************************************************" "White"
				
			If ($VMconfig.NetType -match "vSS") 
			{
				$NICcount = $VMconfig.NICcount
				For($nic=1; $nic -le $NICcount; $nic++) 
				{
					$Network="Network$nic"
					If ($ColumnsCsv_newVMs -notcontains $Network)                     
					{
						Out-Log "`r`n`r***************************************************************************************************************************************************************" "Red"
						Out-Log "`n[ Expected Column: [ $Network ] not found in the DeployVM.csv ]. Please Check it.!" "Red"
						$failReconfig = @($vmName)
					}
					Else 
					{
						If (!($VMconfig.$Network)) 
						{
							Out-Log "`r`n`r***************************************************************************************************************************************************************" "Red"
							Out-Log "`n[ [ $Network ] field is EMPTY for [ $($VMconfig.NewVM) ]. It should be the NETWOTK NAME, Please edit DeployVM.csv" "Red"
							$failReconfig = @($vmName)
						}
						Else 
						{
							$NetworkName = $($VMconfig.$Network)
							$NetworkName_exists = $VM |Get-NetworkAdapter |Where { $VM.NetworkName -eq $NetworkName } -ErrorAction SilentlyContinue
							If ($NetworkName_exists) 
							{                
								Write-Host "`n`...............SKIPPING THIS...................." -ForegroundColor "Yellow"
								Write-Host "`n`The given $Network Adapter with Network Name :: $NetworkName is already attached to the given $VM" -ForegroundColor "Yellow"
								Write-Host "`n`................................................" -ForegroundColor "Yellow"
							}
							Else 
							{
								Write-Host "`n`..................................." -ForegroundColor "Magenta"
								Write-Host "Setting the Virtual Network Adapter to use $NetworkName..."
								If ($nic -eq 1) 
								{
									$VM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $NetworkName -Confirm:$false| Out-Null
									Write-Host "Done."
									Write-Host "`n`..................................." -ForegroundColor "Magenta"
								}
								Else 
								{
									Write-Host "`n`..................................." -ForegroundColor "Magenta"
									Write-Host "Creating a new NetworkAdapter and setting it to use $NetworkName..."
									New-NetworkAdapter -VM $VM -NetworkName $NetworkName -WakeOnLan -StartConnected | Out-Null
									Write-Host "Done."
									Write-Host "`n`..................................." -ForegroundColor "Magenta"
								}
							}
						}
					}
				}
		    }
			Else 
			{
				$NICcount = $VMconfig.NICcount
				Out-log "`nCreating OSCustomizationSpec: [ CustomSpec$vmName ] for VM: [ $vmName ]" "Yellow" 
				$CustomSpec = New-OSCustomizationSpec -Name CustomSpec$vmName -NamingScheme fixed -NamingPrefix $VMconfig.Name -Domain $($VMconfig.Domain) -OSType Linux -DnsServer $VMconfig.pDNS,$VMconfig.sDNS -Type NonPersistent
				Out-Log "`nDeleteing the default NIC mappings from the OSCustomizationSpec: [CustomSpec$vmName]" "Yellow"
				Get-OSCustomizationNicMapping -OSCustomizationSpec $CustomSpec | Remove-OSCustomizationNicMapping -Confirm:$false
				$NICcount = $VMconfig.NICcount
				$input_port = @()
				$exist_port = @()
				$diff_port = @()
				$diff_input_port = @()
					
				For($nic=1; $nic -le $NICcount; $nic++) 
				{
					$Network="Network$nic"
					If ($ColumnsCsv_newVMs -notcontains $Network) 
					{
						Out-Log "`r`n`r***************************************************************************************************************************************************************" "Red"
						Out-Log "`n[ Expected Column: [ $Network ] not found in the DeployVM.csv ]. Please Check it.!" "Red"
						$failReconfig = @($vmName)
					}
					Else 
					{
						If (!$VMconfig.$Network) 
						{
							Out-Log "`r`n`r***************************************************************************************************************************************************************" "Red"
							Out-Log "`n[ [ $Network ] field is EMPTY for [ $($VMconfig.NewVM) ]. It should be the NETWOTK NAME, Please edit DeployVM.csv" "Red"	
							$failReconfig = @($vmName)	  
						}
						Else
						{								
							$input_port += $($VMconfig.$Network)
								
							#$NetworkPort = $($VMconfig.$Network)
							#Write-Host "....$input_port"
						}
					}
				}
							
				$exist_port= (Get-VM $VM | Get-NetworkAdapter).NetworkName
				$diff_input_port=Compare-Object $input_port $exist_port -PassThru | ?{$input_port -notcontains $_} |?{$_.sideIndicator -eq "=>"}
				$diff_input_count=(Compare-Object $input_port $exist_port -PassThru | ?{$input_port -notcontains $_} |?{$_.sideIndicator -eq "=>"}).Count
				#Write-Host "diff_input_port is $diff_input_port"
				
				If($diff_input_port -eq $NULL) 
				{
					Out-Log "`r`nAll the Input Network Adapters for VM: [ $vmName ] match the Network Adapters on the template: [ $($VMconfig.Template) ], proceeding to the customization of the Adapters.." "Green"
				}
				Else 
				{
					Out-Log "`r`nThe Input Network Adapters for VM: [ $vmName ] DOESN'T MATCH the Network Adapters on the template: [ $($VMconfig.Template) ], Removing mismatched Newtwork Adapters" "White"
					$diff_input_port | ForEach-Object { 
						$n = $_; 
						#Out-Log "Removing Network Adapter with Network Name: [  ]" "Yellow"
						#Write-Host "Get-VM $VM | Get-NetworkAdapter | Remove-NetworkAdapter | Where { $_.NetworkName -eq $n } -ErrorAction SilentlyContinue "
						$rm_nic = Get-VM $VM | Get-NetworkAdapter | Where { $_.NetworkName -eq $n } 
						Out-Log "Removing the Network Adapter: [ $rm_nic ] with Network Name: [ $n ]" "Yellow"
						Remove-NetworkAdapter -NetworkAdapter $rm_nic -Confirm:$false
						#Get-VM $VM | Get-NetworkAdapter
						}
				}
					
				For($nic=1; $nic -le $NICcount; $nic++) 
				{
					$Network="Network$nic"
					$NetworkPort_Exists = ''
					$NetworkPort = $($VMconfig.$Network)
					$NetworkPort_Exists = Get-VM $VM | Get-NetworkAdapter | Where { $_.NetworkName -eq $NetworkPort } -ErrorAction SilentlyContinue
					#Get-VM $VM | Get-NetworkAdapter | Where { $_.NetworkName -eq $NetworkPort }
					If ($NetworkPort_Exists) 
					{                
						Out-Log "`r`nNetwork Adapter:[ $Network Adapter ] with Network Name: [ $NetworkPort ] exists on the template" "Green"
						Out-Log "`nApplying OSCustomizationNicMapping to Network Adapter:[ $Network Adapter ]" "Yellow"

						If ($VMconfig."DHCP$nic" -match "TRUE")
						{
							$CustomSpec | New-OSCustomizationNicMapping -IpMode UseDhcp -NetworkAdapterMac $NetworkPort_Exists.MacAddress | Out-Null
						}
						Else
						{
							If($VMconfig."Gateway$nic" -match "NO")
							{
								$CustomSpec | New-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $VMconfig."IPAddress$nic" -SubnetMask $VMconfig."SubnetMask$nic" -NetworkAdapterMac $NetworkPort_Exists.MacAddress | Out-Null
							}
							Else
							{

								$CustomSpec | New-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $VMconfig."IPAddress$nic" -SubnetMask $VMconfig."SubnetMask$nic" -DefaultGateway $VMconfig."Gateway$nic" -NetworkAdapterMac $NetworkPort_Exists.MacAddress | Out-Null
								#$CustomSpec | New-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $($VMconfig."IPAddress$nic") -SubnetMask $($VMconfig."SubnetMask$nic") -DefaultGateway $($VMconfig."Gateway$nic") -NetworkAdapterMac $NetworkPort_Exists.MacAddress
							}
						}             
					}
					Else 
					{
						Out-Log "`r`nAdding New Network Adapter:[ $Network Adapter ] and setting it to use: [ $NetworkPort ]" "Yellow"
						New-NetworkAdapter -VM $VM -Portgroup $NetworkPort -WakeOnLan -StartConnected | Out-Null
						$NetworkPort_Exists = Get-VM $VM | Get-NetworkAdapter | Where { $_.NetworkName -eq $NetworkPort } -ErrorAction SilentlyContinue
						Out-Log "`nApplying OSCustomizationNicMapping to Network Adapter:[ $Network Adapter ]" "Yellow"
						
						If ($VMconfig."DHCP$nic" -match "TRUE")
						{
							$CustomSpec | New-OSCustomizationNicMapping -IpMode UseDhcp -NetworkAdapterMac $NetworkPort_Exists.MacAddress | Out-Null
						}
						Else
						{
							$CustomSpec | New-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $($VMconfig."IPAddress$nic") -SubnetMask $VMconfig."SubnetMask$nic" -DefaultGateway $VMconfig."Gateway$nic" -NetworkAdapterMac $NetworkPort_Exists.MacAddress | Out-Null
						}								
					}
				}
			}
			

			#Applying the OS customizations to the NICs.
			Out-Log "`r`n[ Applying OS Customizations: [ $CustomSpec ] to the VM: [ $vmName ] ***********************************************************" "White"
			Set-VM -VM $VM -OSCustomizationSpec $CustomSpec -Confirm:$false
			
			# Add additional disks if needed
			If ($VMConfig.Disk2 -gt 1) 
			{
				Out-Log "`r`n[ Adding additional disk: [ $($VMConfig.Disk2) ] on VM: [ $vmName ] *************************************************************************" "White"
				Out-log "Don't forget to format disk: [ [ $($VMConfig.Disk2) ]] within the OS" "Yellow"
				$VM | New-HardDisk -CapacityGB $VMConfig.Disk2 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
			}
			If ($VMConfig.Disk3 -gt 1) 
			{
				Out-Log "`r`n[ Adding additional disk: [ $($VMConfig.Disk3) ] on VM: [ $vmName ] *************************************************************************" "White"
				Out-log "Don't forget to format disk: [ [ $($VMConfig.Disk3) ]] within the OS" "Yellow"
				$VM | New-HardDisk -CapacityGB $VMConfig.Disk3 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
			}
			If ($VMConfig.Disk4 -gt 1) 
			{
				Out-Log "`r`n[ Adding additional disk: [ $($VMConfig.Disk4) ] on VM: [ $vmName ] *************************************************************************" "White"
				Out-log "Don't forget to format disk: [ [ $($VMConfig.Disk4) ]] within the OS" "Yellow"
				$VM | New-HardDisk -CapacityGB $VMConfig.Disk3 -StorageFormat $VMConfig.DiskStorageFormat -Persistence persistent | Out-Null
			}


			# Boot VM
			If ($VMconfig.Boot -match "true") 
			{
				Out-Log "`r`n[ Booting: [ $vmName ] ] ************************************************************************************************************" "White"
				$VM | Start-VM
			}
				
			#Removing the OS customization specification that we set earlier (even though we used NonPersistent Type, it is better to remove now
			#NonPersistent only removes Spec when you close the terminal. By removing now, I can run N times the same script in the same terminal.

			Out-Log "`r`n[ Removing the OS Customization Specs Created During the Script Execution ] *********************************************************" "White"
			Out-Log "Deleting: [ $CustomSpec ]" "Yellow"
			Remove-OSCustomizationSpec $CustomSpec -Confirm:$false

			$taskTab.Remove($_.Id)
			$runningTasks--
			Out-Log "`r`n[ RunningTasks Count: $runningTasks] ****************************************************************************************************" "Cyan"
			Out-Log "`r`n***************************************************************************************************************************************************************" "White"
			If ($Error.Count -ne 0) 
			{
				Out-Log "$vmName completed with errors" "Red"
				Out-Log "`nVM: [ $vmName ] completed with errors`n" "Red"
				Foreach ($err in $Error) {
					Out-Log "$Err" "Red"
				}
				$failReconfig += @($vmName)
			} 
			Else 
			{
				Out-Log "`VM: [ $vmName ] completed without any errors`n" "Green"
				$successVMs += @($vmName)
			}
		}
		Elseif($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error")
		{
			Write-Host ($taskTab | Out-String) -ForegroundColor Yellow
			Write-Host $_.Id -ForegroundColor Cyan
			# Deployment failed
			$failed = $taskTab[$_.Id]
			Out-Log "`n[ $failed ] failed to deploy!`n" "Red"
			$taskTab.Remove($_.Id)
			$runningTasks--
			Out-Log "`r`n[ RunningTasks Count: $runningTasks] ****************************************************************************************************" "Cyan"
			$failDeploy += @($failed)
		}
		Elseif($taskTab.ContainsKey($_.Id) -and $_.State -eq "Running")
		{
			$retrieve_VMname = ($_.Id)
			Write-Host "retrieve_VMname is : $retrieve_VMname" -ForegroundColor "Yellow"
			Out-Log "`r`n[ The Task of Deploying VM is still running for : $($taskTab.Item($retrieve_VMname)) ] ****************************************************************************************************" "Cyan"
			Start-Sleep -Seconds 5
		}
		
	}
	#Start-Sleep -Seconds 5
}



#--------------------------------------------------------------------
# Close Connections

Out-Log "`r`n[ Disconnecting to vCenter: $($vCenter.vCenter) ] ************************************************************************************************************" "Yellow"
Disconnect-VIServer -Server $($vCenter.vCenter) -Force -Confirm:$false

#--------------------------------------------------------------------
# Outputs

Out-Log "`r`n***************************************************************************************************************************************************************" "White"
Out-Log "`n[ Processing Completed ] " "Green"
Out-Log "`n***************************************************************************************************************************************************************" "White"

If ($successVMs -ne $null) {
    Out-Log "`n[ The following VMs were successfully created ] ***************************************************************************************************************" "White"
    Foreach ($success in $successVMs) {Out-Log "$success" "Green"}
}
If ($failReconfig -ne $null) {
    Out-Log "`n[ The following VMs failed to reconfigure properly ] **********************************************************************************************************" "White"
    Foreach ($reconfig in $failReconfig) {Out-Log "$reconfig" "Red"}
}
If ($failDeploy -ne $null) {
    Out-Log "`n[ The following VMs failed to deploy ] ************************************************************************************************************************" "White"
    Foreach ($deploy in $failDeploy) {Out-Log "$deploy" "Red"}
}


$finishtime = Get-Date -uformat "%m-%d-%Y %I:%M:%S"
Out-Log "`n`n"
Out-Log "***************************************************************************************************************************************************************"
Out-Log "$scriptName`t`t`t`t`tFinish Time:`t$finishtime"
Out-Log "***************************************************************************************************************************************************************"


# Get End Time
$endDTM = (Get-Date)

# Time elapsed
$ET=$($endDTM-$startDTM)
#Out-Log "`n`n"
#Out-Log "***************************************************************************************************************************************************************"
Out-Log "TIME ELAPSED FOR SCRIPT EXECUTION -->`t$(($endDTM-$startDTM).TotalHours) Hours, $(($endDTM-$startDTM).TotalMinutes) Minutes and $(($endDTM-$startDTM).TotalSeconds) seconds"
Out-Log "***************************************************************************************************************************************************************"
