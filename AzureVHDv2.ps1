#############################################################################
#                                     			 		                    #
#   This Sample Code is provided for the purpose of illustration only       #
#   and is not intended to be used in a production environment.  THIS       #
#   SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT    #
#   WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT    #
#   LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS     #
#   FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free    #
#   right to use and modify the Sample Code and to reproduce and distribute #
#   the object code form of the Sample Code, provided that You agree:       #
#   (i) to not use Our name, logo, or trademarks to market Your software    #
#   product in which the Sample Code is embedded; (ii) to include a valid   #
#   copyright notice on Your software product in which the Sample Code is   #
#   embedded; and (iii) to indemnify, hold harmless, and defend Us and      #
#   Our suppliers from and against any claims or lawsuits, including        #
#   attorneys' fees, that arise or result from the use or distribution      #
#   of the Sample Code.                                                     #
#                                     			 		                    #
#   Version 2.0                              			 	                #
#   Last Update Date: 26 July 2017                           	            #
#                                     			 		                    #
#############################################################################

#Requires -version 4
#Requires -module AzureRM.Profile,AzureRM.Compute,AzureRM.Storage

Param([String[]]$ExcludedStorageAccount)
Login-AzureRmAccount -ErrorVariable loginerror

If ($loginerror -ne $null)
{
Throw {"Error: An error occured during the login process, please correct the error and try again."}
}

Function Select-Subs
{
$ErrorActionPreference = 'SilentlyContinue'
$Menu = 0
$Subs = @(Get-AzureRmSubscription | select Name,ID,TenantId)

Write-Host "Please select the subscription you want to use" -ForegroundColor Green;
$Subs |%{Write-Host "[$($Menu)]" -ForegroundColor Cyan -NoNewline ;Write-host ". $($_.Name)";$Menu++;
}
$selection = Read-Host "Please select the Subscription Number - Valid numbers are 0 - $($Subs.count -1)"
If ($Subs.item($selection) -ne $null)
{
Return @{name = $subs[$selection].Name;ID = $subs[$selection].ID}
}



}
$SubscriptionSelection = Select-Subs
Select-AzureRmSubscription -SubscriptionName $SubscriptionSelection.Name -ErrorAction Stop


Write-Host "Retrieving all VHD URI's from Storage Account" -ForegroundColor Green

$Data = @{}
$StorageAccountLoopCount = 0
$StorageAccounts = @(Get-AzureRmStorageAccount | ?{$_.StorageAccountName -notin @($ExcludedStorageAccount)})

Foreach ($StorageAccount in $StorageAccounts)
{   
    $StorageAccountLoopCount++
    $StorageAccountPercentComplete = $StorageAccountLoopCount/$StorageAccounts.Count*100    
    Write-Progress -Activity "StorageAccount Progress ($($StorageAccountLoopCount)/$($StorageAccounts.Count)):" -Status "StorageAccount: $($StorageAccount.StorageAccountName)" -PercentComplete $StorageAccountPercentComplete -Id 1

    $StorageAccountContainerLoopCount = 0
    $StorageAccountContainers = @(Get-AzureStorageContainer -Context $StorageAccount.Context )
    
       Foreach ($StorageAccountContainer in $StorageAccountContainers)
       {
            $StorageAccountContainerLoopCount++
            $StorageAccountContainerPercentComplete = $StorageAccountContainerLoopCount/$StorageAccountContainers.Count*100
            Write-Progress -Activity "StorageAccount Container Progress ($($StorageAccountContainerLoopCount)/$($StorageAccountContainers.Count)):" -Status "StorageAccount Container: $($StorageAccountContainer.Name)" -PercentComplete $StorageAccountContainerPercentComplete -Id 2 -ParentId 1

           
            Foreach ($blob in @(Get-AzureStorageBlob -Container $StorageAccountContainer.Name -Context $StorageAccount.Context -Blob "*.vhd"))
            { 
             
                IF ($blob.BlobType -eq "PageBlob")
                {
                 
                 $data."$($blob.Name)" = [PSCustomObject]@{Container = $StorageAccountContainer.Name
                                          StorageAccount = $StorageAccount.StorageAccountName 
                                          VMName = '' 
                                          vhd = $blob.Name
                                          'Size(GB)' = [Math]::Round($blob.length /1GB,0)
                                          Sku = "[$($StorageAccount.Sku.Name)] $($StorageAccount.Sku.Tier)"
                                          LastModified = $blob.LastModified.ToString()}
                }
            }
        }
}

Write-host "Retrieving all VM's" -ForegroundColor green
$allVMS = @(Get-AzureRMVM -WarningAction SilentlyContinue )
foreach ($VM in $allVMS)
    {
    $ErrorActionPreference = 'SilentlyContinue'
    $disks = [System.Collections.ArrayList]::new() 
    $disks.add($vm.StorageProfile.OsDisk.vhd.uri.Replace('%7B','{').replace('%7D','}')) | Out-Null
    $vm.StorageProfile.DataDisks.vhd.uri | %{$disks.Add("$($_.Replace('%7B','{').replace('%7D','}'))")} | Out-Null
    $disk = [System.Collections.ArrayList]::new()
    $disks |  %{ if (($_ -Split '/')[-1] -ne ''){$Data."$(($_ -Split '/')[-1])".VMName = $VM.Name} }
    }

Write-Host "Comparing results" -ForegroundColor Green


$CSS = @"
<Title>Capacity Report:$(Get-Date -Format 'dd MMMM yyyy' )</Title>
<Style>
th {
	font: bold 11px "Trebuchet MS", Verdana, Arial, Helvetica,
	sans-serif;
	color: #FFFFFF;
	border-right: 1px solid #C1DAD7;
	border-bottom: 1px solid #C1DAD7;
	border-top: 1px solid #C1DAD7;
	letter-spacing: 2px;
	text-transform: uppercase;
	text-align: left;
	padding: 6px 6px 6px 12px;
	background: #5F9EA0;
}
td {
	font: 11px "Trebuchet MS", Verdana, Arial, Helvetica,
	sans-serif;
	border-right: 1px solid #C1DAD7;
	border-bottom: 1px solid #C1DAD7;
	background: #fff;
	padding: 6px 6px 6px 12px;
	color: #6D929B;
}
</Style>
"@

($data.Keys | %{$data.$_ } | Sort-Object -Property VMName,LastModified | `
Select @{Name='VMName';E={IF ($_.VMName -eq ''){'Not Attached'}Else{$_.VMName}}},StorageAccount,Container,vhd,Size*,Sku,LastModified |`
ConvertTo-Html -Head $CSS ).replace('Not Attached','<font color=red>Not Attached</font>').replace('Premium','<font color=black><b>Premium</b></font>')| Out-File ".\$($SubscriptionSelection.Name)_VHDReport.html"
Invoke-Item ".\$($SubscriptionSelection.Name)_VHDReport.html"

