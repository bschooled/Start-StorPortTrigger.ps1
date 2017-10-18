################################################################################# 
#  
# The sample scripts are not supported under any Microsoft standard support  
# program or service. The sample scripts are provided AS IS without warranty  
# of any kind. Microsoft further disclaims all implied warranties including, without  
# limitation, any implied warranties of merchantability or of fitness for a particular  
# purpose. The entire risk arising out of the use or performance of the sample scripts  
# and documentation remains with you. In no event shall Microsoft, its authors, or  
# anyone else involved in the creation, production, or delivery of the scripts be liable  
# for any damages whatsoever (including, without limitation, damages for loss of business  
# profits, business interruption, loss of business information, or other pecuniary loss)  
# arising out of the use of or inability to use the sample scripts or documentation,  
# even if Microsoft has been advised of the possibility of such damages 
# 
#################################################################################
param(
    [Parameter(Position=0,Mandatory=$True,HelpMessage="Specify the output directory for the Process dump")]    
    $Directory,
    [switch]$verbose
    )
if($verbose -eq $true){
    $VerbosePreference = "Continue"
    Start-Transcript Verbose-Log.Txt
    }
$date = Get-Date -Format 'yyyyMMdd'
[string]$reportpath = ($directory.Trim("\",""))
#check if log file exists
If (!(Test-Path -path "$Global:Log")) {New-Item "$Global:Log" -type directory}
$Global:Log = "$reportpath\StorPortTrigger-$yyyyMMdd-Logging.txt"

[bool]$loop = $true
[string]$readcounter = "\LogicalDisk(*)\Avg. Disk sec/Write"
[string]$queuecounter = "\LogicalDisk(*)\Current Disk Queue Length"
[int]$storcount = 1

function storport($storcount){
    $date = get-date -f yyyy-MM-dd
    $dir = "D:\procdump\"
    $stname = $dir + "storport-$date-$storcount.etl"
    $storport = 'logman create trace "drivers_storage" -ow -o ' + $stname + ' -p "Microsoft-Windows-StorPort" 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 4096 -ets'
    return $storport
    }
function checkcounter($name,$counter,$started){   
    [int]$thresh = threshold $name
    [bool]$start = $false
    $sw = New-Object -typename System.IO.StreamWriter("$($Global:Log)", "true");
    $sw.WriteLine("`nCounter: $name");
    
    foreach($dr in $counter){
        $countervalue = @($dr.CounterSamples)
        if($countervalue.Count -gt 1){
	        $sw.WriteLine("`nMultiple CounterSamples");
            
            foreach($cv in $countervalue){
                $counterpath = $cv.Path
                [int]$cooked = $cv.CookedValue
                $sw.WriteLine("`nPath = $counterpath ; Cooked = $cooked ; Threshold = $thresh");
                
                if($cooked -gt $thresh){
                    if($started -like $false){
                        $sw.WriteLine("`nCounter $name > $thresh , Starting Trace`n");
                        
                        }
                    [bool]$start = $true
                    }
                else{
                    [bool]$start = $false
                    }
                }
            $sw.Close()
            }
        else{
	        $sw.WriteLine("`nSingle CounterSample");
            
            $counterpath = $cv[0].Path
            [int]$cooked = $cv[0].CookedValue
            $sw.WriteLine("`nPath = $counterpath ; Cooked = $cooked ; Threshold = $thresh");
            
            if($cooked -gt $thresh){
                if($started -like $false){
                    $sw.WriteLine("`nCounter $name > $thresh , Starting Trace`n");
                    $sw.Close()
                    }
                [bool]$start = $true
                }
            else{
                [bool]$start = $false
                }
            $sw.Close()
            }
        }   
    return [bool]$start
    }
function threshold($name){
    $sw = New-Object -typename System.IO.StreamWriter("$Global:Log", "true");
    switch ($name){
            "\LogicalDisk(*)\Avg. Disk sec/Write"{
	        $sw.WriteLine("`nMatches Disk Write, Returning 20");
            
            [int]$threshold = 20
            }
            "\LogicalDisk(*)\Current Disk Queue Length"{
	        $sw.WriteLine("`nMatches Disk Queue Length, Returning 5");
            
            [int]$threshold = 5
            }
        }
    $sw.Close()
    return [int]$threshold
    }
while($loop -eq $true){
    [bool]$started = $false
    [array]$diskread = Get-Counter -Counter $readcounter
    [array]$diskqueue = Get-Counter -Counter $queuecounter
    $traceconditionread = checkcounter $readcounter $diskread $started
    $traceconditionqueue = checkcounter $queuecounter $diskqueue $started
    $sw = New-Object -typename System.IO.StreamWriter("$Global:Log", "true");
    $sw.WriteLine("`nPre-Storport Trace Start Conditions");
    $sw.WriteLine("`nTrace Condition Read: $traceconditionread");
    $sw.WriteLine("`nTrace Condition Queu: $traceconditionqueue");
    $sw.Close()
    if($traceconditionread -like $true -or $traceconditionqueue -like $true){
       $expression = storport $storcount
       Invoke-Expression $expression
       [bool]$wait = $true
       [int]$exitcounter = 0
       while($wait -eq $true){          
            [bool]$started = $true
            [array]$diskread = Get-Counter -Counter $readcounter
            [array]$diskqueue = Get-Counter -Counter $queuecounter
            $traceconditionread = checkcounter $readcounter $diskread $started
            $traceconditionqueue = checkcounter $queuecounter $diskqueue $started
            $sw = New-Object -typename System.IO.StreamWriter("$Global:Log", "true");
            $sw.WriteLine("`nPost-Storport Trace Start Conditions");
            $sw.WriteLine("`nTrace Condition Read: $traceconditionread");
            $sw.WriteLine("`nTrace Condition Queue: $traceconditionqueue");
            
            if($traceconditionread -like $false -and $traceconditionqueue -like $false){
                [int]$exitcounter++
                $sw.WriteLine("`nExit Counter: $exitcounter");
                
                if($exitcounter -gt 12){
                    $sw.WriteLine("`nCounters have fallen over 60 second period ... Ending Trace`n");
                    
                    logman.exe stop -ets "drivers_storage"
                    [bool]$wait = $false
                    }
                Start-Sleep -Seconds 5
                }
            else{
                $sw.WriteLine("`nTrace is started, checking counters and waiting");
                
                Start-Sleep -Seconds 5
                }
            $sw.Close()
            }
            [int]$storcount++            
        }
    else{
        $sw = New-Object -typename System.IO.StreamWriter("$Global:Log", "true");
        $sw.WriteLine("`nCounters have not exceeded threshold ... Waiting");
        Start-Sleep -Seconds 5
        $sw.Close()
        }
    }
if($verbose -eq $true){
    $VerbosePreference = "SilentlyContinue"
    Stop-Transcript
    }