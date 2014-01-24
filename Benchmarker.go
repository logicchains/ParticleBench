/*	Reads data from BenchmarkData.dat (three rows per language, first is name, second is compile command or "-" if interpreted, third is run command).
	If flag -c=true is set, compiles the languages read from that file and records their compile time.
	Runs them.
	Outputs their framerate data to FrameFile, runs Frames2PPM.go and saves the output to LangName.ppm
	Outputs their framerate and compile time to stdout.
*/

package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"os/exec"
	"strings"
	"time"
)

const (
	langFile  = "BenchmarkData.dat"
	FrameFile = "Frames.dat"
)

var (
	langs     []Lang
	dataLines []string
)

type Lang struct {
	Name        string
	Commands    string
	Run         string
	CmplTime    float64
	Results     string
	Loaded      bool
	Interpreted bool
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
	for i := 0; i < len(dataLines)-1; i += 3 {
		thisLang := Lang{Name: dataLines[i], Commands: dataLines[i+1], Run: dataLines[i+2], Loaded: true, Interpreted: dataLines[i+1] == "-"}
		langs = append(langs, thisLang)
	}
}

func compileLangs() {
	for i, lang := range langs {
		if lang.Interpreted == true {
			continue
		}
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
		out, err := runCommand(lang.Run)
		if err != nil {
			fmt.Printf("Running %v failed with error of %v", lang.Name, err)
			langs[i].Loaded = false
		}
		langs[i].Results = string(out)
	}
}

func graphLangs() {
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
	for _, lang := range langs {
		if lang.Loaded == false {
			continue
		}
		var fps string
		var cpuTime string
		if strings.Index(lang.Results, ":") < 0 || strings.Index(lang.Results, " frames") < 0 {
			fmt.Printf("Failed to read framerate results for language %v\n", lang.Name)
			fps = "N/A"
		}else {
			fps = strings.TrimSpace(lang.Results[strings.Index(lang.Results, ":")+1 : strings.Index(lang.Results, " frames")])
		}
		if strings.Index(lang.Results, "was-") < 0 || strings.Index(lang.Results, " seconds") < 0 {
			fmt.Printf("Failed to read cpu time results for language %v\n", lang.Name)
			cpuTime = "N/A"
		}else {
			cpuTime = strings.TrimSpace(lang.Results[strings.Index(lang.Results, "was-")+4 : strings.Index(lang.Results, " seconds")])
		}
		fmt.Printf("The implementation in language %v compiled in %v seconds and ran with an average framerate of %v frames per second and an average cpu time of %v seconds per frame.\n", lang.Name, lang.CmplTime, fps, cpuTime)
	}
}

var cflag = flag.Bool("c", true, "Whether to compile")

func runCommand(command string) (string, error){
	script := "#!/bin/bash\n" + command
	err := ioutil.WriteFile("command.sh", []byte(script), 0644)
	if err != nil {
		fmt.Printf("Failed to write command %v, with error: %v", command, err)
		return "", err
	}
	cmdOutput, err2 := exec.Command("sh", "command.sh").CombinedOutput()
	if err2 != nil {
		fmt.Printf("Failed to exec command %v, failing with error %v", command, err2)
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
}
