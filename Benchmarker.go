/*	Reads data from BenchmarkData.dat (four rows per language, first is name, second is compile command or "-" if interpreted, third is run command, fourth is source file name).
	If flag -c=true is set, compiles the languages read from that file and records their compile time.
	Runs them, recording their resident memory usage.
	Waits WaitTime seconds between each run.
	Outputs their framerate data to FrameFile, runs Frames2PPM.go and saves the output to LangName.ppm
	Outputs their framerate, memory usage and compile time to stdout.
	Compresses their source files and records their size.
	Outputs all the above data to an HTML table in ResultsTable.html
*/

package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"strconv"
	"os/exec"
	"bytes"
	"strings"
	"time"
	"text/template"
	"unicode"
)

const (
	langFile  = "BenchmarkData.dat"
	FrameFile = "Frames.dat"
	WaitTime = 90 
)

var (
	langs     []Lang
	dataLines []string
)

type Lang struct {
	Name        string
	Commands    string
	Run         string
	Filename    string
	CmplTime    float64
	Results     string
	Loaded      bool
	Interpreted bool
	FPS	    float64
	PcntMaxFps  float64
	CpuTime     float64
	PcntMinCpu  float64
	Compiler    string
	MemUse	    int64
	CompSize    int64
}

func loadLangs() {
	contents, err := ioutil.ReadFile(langFile)
	if err != nil {
		panic(err)
	}
	dataLines = strings.Split(string(contents), "\n")
	for i, _ := range dataLines {
		dataLines[i] = strings.Trim(dataLines[i], "\n\r")
	}
	for i := 0; i < len(dataLines)-1; i += 4 {
		thisLang := Lang{Name: dataLines[i], Commands: dataLines[i+1], Run: dataLines[i+2], Filename: dataLines[i+3], Loaded: true, Interpreted: dataLines[i+1] == "-"}
		langs = append(langs, thisLang)
	}
}

func compileLangs() {
	for i, lang := range langs {
		if lang.Interpreted == true {
			continue
		}
		fmt.Printf("Now compiling language %v.\n", lang.Name)
		initT := time.Now()
		_, err := runCommand(lang.Commands)
		if err != nil {
			fmt.Printf("Compilation of %v failed with error of %v", lang.Name, err)
			langs[i].Loaded = false
		}
		endT := time.Now()
		langs[i].CmplTime = endT.Sub(initT).Seconds()
	}

}

func runLangs() {
	for i, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		fmt.Println("Pausing to allow the system to cool down.")
		time.Sleep(WaitTime * time.Second)
		fmt.Printf("Now running language %v.\n", lang.Name)
		out, err := runCommand(`command time -f 'max resident:\t%M KiB' ` + lang.Run)
		if err != nil {
			fmt.Printf("Running %v failed with error of %v", lang.Name, err)
			langs[i].Loaded = false
		}
		langs[i].Results = string(out)
	}
}

func graphLangs() {
	fmt.Println("Now graphing framerate results.")
	for _, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		if strings.Index(lang.Results, "--:") < 0 || strings.Index(lang.Results, ".--") < 0 {
			fmt.Printf("Could not read frame data for language %v.\n", lang.Name)
			continue
		}
		frames := strings.TrimSpace(lang.Results[strings.Index(lang.Results, "--:")+3 : strings.Index(lang.Results, ".--")-1])
		err := ioutil.WriteFile(FrameFile, []byte(frames), 0644)
		if err != nil {
			fmt.Printf("Failed to write frames to file for language %v, failing with error %v\n", lang.Name, err)
			continue
		}
		graphFile := lang.Name + ".ppm"
		ppmDat, err2 := exec.Command("go", "run", "Frames2PPM.go").Output()
		if err2 != nil {
			fmt.Printf("Graphing %v via Frames2PPM.go failed with error of %v\n", lang.Name, err)
			continue
		}
		err3 := ioutil.WriteFile(graphFile, []byte(ppmDat), 0644)
		if err3 != nil {
			fmt.Printf("Failed to write ppm graph to file for language %v, failing with error %v\n", lang.Name, err)
			continue
		}

	}
}

func printLangs() {
	for i, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		var fps string
		var cpuTime string
		var memUse string
		if strings.Index(lang.Results, "framerate was:") < 0 || strings.Index(lang.Results, " frames") < 0 {
			fmt.Printf("Failed to read framerate results for language %v\n", lang.Name)
			fps = "N/A"
		}else {
			fps = strings.TrimSpace(lang.Results[strings.Index(lang.Results, "framerate was:")+14 : strings.Index(lang.Results, " frames")])
			langs[i].FPS, _ = strconv.ParseFloat(fps, 32) 
		}
		if strings.Index(lang.Results, "was-") < 0 || strings.Index(lang.Results, " seconds") < 0 {
			fmt.Printf("Failed to read cpu time results for language %v\n", lang.Name)
			cpuTime = "N/A"
		}else {
			cpuTime = strings.TrimSpace(lang.Results[strings.Index(lang.Results, "was-")+4 : strings.Index(lang.Results, " seconds")])
			langs[i].CpuTime, _ = strconv.ParseFloat(cpuTime, 32) 
		}
		if strings.Index(lang.Results, "resident:") < 0 || strings.Index(lang.Results, "KiB") < 0 {
			fmt.Printf("Failed to read memory usage results for language %v\n", lang.Name)
			memUse = "N/A"			
		}else {
			tmpStr := strings.TrimSpace(lang.Results[strings.Index(lang.Results, "resident:"):])
			memUse = tmpStr[strings.Index(tmpStr, "resident:") + 9 : strings.Index(tmpStr, "KiB")]
			memUse = strings.TrimFunc(memUse, func(r rune) bool{return !unicode.IsDigit(r)} )			
			var err error
			langs[i].MemUse, err = strconv.ParseInt(memUse,10,32)
			if err != nil{
				fmt.Printf("Error parsing memory use to integer for language %v\n", lang.Name)
			} 
		}
		fmt.Printf("The implementation in language %v compiled in %v seconds and ran with an average framerate of %v frames per second and an average cpu time of %v seconds per frame, using %v KiB of memory.\n", lang.Name, lang.CmplTime, fps, cpuTime, memUse)
	}
}

func measureLangSizes(){
	fmt.Println("Now measuring compressed source file sizes.")
	for i, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		runCommand("bzip2 -k " + lang.Filename)
		size, err := runCommand("du -b " + lang.Filename + ".bz2")
		if err != nil{
			fmt.Printf("Error of: %v when reading compressed source file size for language %v\n", err, lang.Name)
			continue
		}
		intSize, err := strconv.ParseInt(strings.TrimSpace(size[:len(size)-len(lang.Filename + ".bz2")-1]),10,32)
		if err != nil{
			fmt.Printf("Error of: %v when parsing compressed source file size to int for language %v\n", err, lang.Name)
			continue
		}
		langs[i].CompSize = intSize
		_,_ = runCommand("rm " + lang.Filename +".bz2")
	}
}

func calcLangStats(){
	fmt.Println("Now calculating summary statistics")
	maxFps := 0.0
	minCpuTime := 100.0	
	for _, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		if lang.CpuTime < minCpuTime && lang.CpuTime > 0.0001{
			minCpuTime = lang.CpuTime
		}
		if lang.FPS > maxFps && lang.CpuTime < 1000{
			maxFps = lang.FPS
		}
	}
	for i, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		langs[i].PcntMaxFps = lang.FPS/maxFps
		langs[i].PcntMinCpu = minCpuTime/lang.CpuTime
		langs[i].Compiler = strings.Split(lang.Commands, " ")[0]
	}
}

func putResultsInHtmlTable() {
	tmpl, err := template.New("row").Parse(`
		<tr>
		<td style="text-align: center;" width="81" height="17"><span style="color: #000000;"><em>{{.Name}}</em></span></td>
		<td style="text-align: center;" width="81"><span style="color: #000000;"><em>{{.Compiler}}</em></span></td>
		<td style="text-align: center;" width="81"><span style="color: #000000;"><em>{{printf "%.4f" .CmplTime}}</em></span></td>
		<td style="text-align: center;" width="81"><span style="color: #000000;"><em>{{printf "%.2f" .FPS}}</em></span></td>
		<td style="text-align: center;" width="81"><span style="color: #000000;"><em>{{printf "%.2f" .PcntMaxFps}}</em></span></td>
		<td style="text-align: center;" width="81"><span style="color: #000000;"><em>{{printf "%.5f" .CpuTime}}</em></span></td>
		<td style="text-align: center;" width="81"><span style="color: #000000;"><em>{{printf "%.2f" .PcntMinCpu}}</em></span></td>
		<td style="text-align: center;" width="70"><span style="color: #000000;"><em>{{.MemUse}}</em></span></td>
		<td style="text-align: center;" width="70"><span style="color: #000000;"><em>{{.CompSize}}</em></span></td>
		</tr>
	`)
	table := `
		<table width="394" border="1" cellspacing="1" cellpadding="1">
		<colgroup>
			<col span="4" width="81" />
			<col width="70" />
		</colgroup>
		<tbody>
			<tr>
			<td style="text-align: center;" width="81" height="17"><span style="color: #000000;"><em>Language</em></span></td>
			<td style="text-align: center;" width="81"><span style="color: #000000;"><em>Compiler</em></span></td>
			<td style="text-align: center;" width="81"><span style="color: #000000;"><em>Compile Time</em></span></td>
			<td style="text-align: center;" width="81"><span style="color: #000000;"><em>Framerate</em></span></td>
			<td style="text-align: center;" width="81"><span style="color: #000000;"><em>% Fastest</em></span></td>
			<td style="text-align: center;" width="81"><span style="color: #000000;"><em>CPU time</em></span></td>
			<td style="text-align: center;" width="81"><span style="color: #000000;"><em>% Fastest</em></span></td>
			<td style="text-align: center;" width="70"><span style="color: #000000;"><em>Resident mem use (KiB)</em></span></td>
			<td style="text-align: center;" width="70"><span style="color: #000000;"><em>Compressed source size</em></span></td>
			</tr>
	`

	for _, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		var execResults bytes.Buffer 
		err = tmpl.Execute(&execResults, lang)		
		table += execResults.String() 
	}

	table = table + `
		</tbody>
		</table>`

	err = ioutil.WriteFile("ResultsTable.html", []byte(table), 0644)
	if err != nil {
		fmt.Printf("Failed to write results to HTML table, failing with error %v\n", err)
	}
}

var cflag = flag.Bool("c", true, "Whether to compile")

func runCommand(command string) (string, error){
	script := "#!/bin/bash\n" + command
	err := ioutil.WriteFile("command.sh", []byte(script), 0644)
	if err != nil {
		fmt.Printf("Failed to write command %v, with error: %v\n", command, err)
		return "", err
	}
	cmdOutput, err2 := exec.Command("sh", "command.sh").CombinedOutput()
	if err2 != nil {
		fmt.Printf("Failed to exec command %v, failing with error %v: %v\n", command, err2, string(cmdOutput))
		return "", err2
	}
	return string(cmdOutput), nil
}

func main() {
	flag.Parse()
	loadLangs()
	var cmp bool = *cflag
	if cmp == true {
		compileLangs()
	}
	runLangs()
	graphLangs()
	printLangs()
	measureLangSizes()
	calcLangStats()
	putResultsInHtmlTable()
}
