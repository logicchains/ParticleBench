/*	Opens FrameFile, outputs a bar graph representing their framerate over time. Horizontal axis is their framerate/MaxFramerate.
	If relativeGraphs == true, horizontal axis is their framerate/(their maximum framerate).
	Vertical axis is time.
*/

package main

import (
	"fmt"
	"io/ioutil"
	"strconv"
	"strings"
)

const FrameFile = "Frames.dat"
const PixelWidth = 400
const PixelHeight = 600
const Fill = "255 255 255"
const Empty = "0 0 0"
const MaxFramerate = 100
const relativeGraphs = false

type Row struct {
	Val           float64
	NormalisedVal int
	Cells         []string
}

func decRes(arr []string) []string {
	tmp := make([]string, 0, len(arr))
	for i, arr := range arr {
		if i%4 == 0 {
			continue
		}
		tmp = append(tmp, arr)
	}
	return tmp
}

func main() {
	frames, err := ioutil.ReadFile(FrameFile)
	if err != nil {
		panic(err)
	}
	splitData := strings.Split(string(frames), ",")
	for len(splitData) > PixelHeight {
		splitData = decRes(splitData)
	}
	floatData := make([]float64, 0, len(splitData))
	for _, str := range splitData {
		trimmedStr := strings.TrimSpace(str)
		float, err := strconv.ParseFloat(trimmedStr, 64)
		if err != nil {
			fmt.Println("Failed at passing one of the input to float")
			continue
		}
		floatData = append(floatData, float)
	}
	max := 0.0
	for _, float := range floatData {
		if float > max {
			max = float
		}
	}
	if relativeGraphs == false {
		max = MaxFramerate
	}
	rows := make([]Row, 0, len(floatData))
	for _, float := range floatData {
		row := Row{Val: float, NormalisedVal: int((float / max) * PixelWidth)}
		cells := make([]string, PixelWidth)
		for i := 0; i < PixelWidth; i++ {
			if i < row.NormalisedVal {
				cells[i] = Fill
			} else {
				cells[i] = Empty
			}
		}
		row.Cells = cells
		rows = append(rows, row)
	}

	fmt.Printf("P3\n%v %v\n255\n", PixelWidth, PixelHeight)
	for _, row := range rows {
		for i, cell := range row.Cells {
			fmt.Print(cell)
			if i == len(row.Cells)-1 {
				fmt.Print("\n")
			} else {
				fmt.Print(" ")
			}
		}
	}
}
