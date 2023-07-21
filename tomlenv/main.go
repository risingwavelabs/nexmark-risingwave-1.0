package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"os"
	"os/user"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"
	"golang.org/x/exp/constraints"
)

var (
	ErrOnCollision = true
)

func init() {
	rand.Seed(time.Now().UnixNano())
}

var alphabet = []rune("abcdefghijklmnopqrstuvwxyz0123456789")

func RandomStr(n int) string {
	alphabetSize := len(alphabet)

	var sb strings.Builder
	for i := 0; i < n; i++ {
		ch := alphabet[rand.Intn(alphabetSize)]
		sb.WriteRune(ch)
	}
	s := sb.String()

	return s
}

type BuiltinFunction interface {
	Execute(args ...string) (string, error)
}

type bfRandom struct{}

func (f bfRandom) Execute(args ...string) (string, error) {
	if len(args) < 1 {
		return "", errors.New("needs at least 1 arguments")
	}
	n, err := strconv.Atoi(args[0])
	if err != nil {
		return "", err
	}
	return RandomStr(n), nil
}

type bfUsername struct{}

func (f bfUsername) Execute(args ...string) (string, error) {
	cur, err := user.Current()
	if err != nil {
		return "", err
	}
	return strings.ReplaceAll(
		strings.ReplaceAll(cur.Name, ".", "-"),
		"_", "-",
	), nil
}

type bfEnv struct{}

func (b bfEnv) Execute(args ...string) (string, error) {
	if len(args) < 1 {
		return "", errors.New("required environment variable name")
	}
	if len(args) > 1 {
		return "", errors.New("too many arguments")
	}
	if value, ok := os.LookupEnv(args[0]); !ok {
		return "", fmt.Errorf("environment variable \"%s\" not found", args[0])
	} else {
		return value, nil
	}
}

var builtinFunctions = map[string]BuiltinFunction{
	"random":   bfRandom{},
	"username": bfUsername{},
	"env":      bfEnv{},
}

var bfPattern = regexp.MustCompile("\\$\\$.+\\(.*\\)")

func renderStr(s string) (string, error) {
	var err error

	r := bfPattern.ReplaceAllStringFunc(s, func(bfs string) string {
		if err != nil {
			return ""
		}

		bfExpr := bfs
		leftParenIndex := strings.Index(bfExpr, "(")
		bfName := bfExpr[2:leftParenIndex]

		bf, found := builtinFunctions[bfName]
		if !found {
			err = errors.New("undefined builtin function: " + bfName)
			return ""
		}

		args := strings.Split(bfs[leftParenIndex+1:len(bfs)-1], ",")
		for i := range args {
			args[i] = strings.TrimSpace(args[i])
		}

		var r string
		r, err = bf.Execute(args...)
		return r
	})
	if err != nil {
		return "", err
	}

	return r, nil
}

func concatenatePrefixes(a, b string) string {
	if a == "" {
		return strings.ToUpper(b)
	}
	return a + "_" + strings.ToUpper(b)
}

func getSortedKeys[K constraints.Ordered, V any](m map[K]V) []K {
	keys := make([]K, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		return keys[i] < keys[j]
	})
	return keys
}

func toEnvVariables(v interface{}) (map[string]string, error) {
	m := make(map[string]string)
	if err := traverseAndCollect(v, "", m); err != nil {
		return nil, err
	}
	return m, nil
}

func traverseAndCollect(v interface{}, prefix string, m map[string]string) error {
	switch v := v.(type) {
	case map[string]interface{}:
		for k := range v {
			if err := traverseAndCollect(v[k], concatenatePrefixes(prefix, k), m); err != nil {
				return err
			}
		}
	case []map[string]interface{}:
		for i, v := range v {
			if err := traverseAndCollect(v, concatenatePrefixes(prefix, strconv.Itoa(i)), m); err != nil {
				return err
			}
		}
	case []interface{}:
		for i, v := range v {
			if err := traverseAndCollect(v, concatenatePrefixes(prefix, strconv.Itoa(i)), m); err != nil {
				return err
			}
		}
	case string:
		s, err := renderStr(v)
		if err != nil {
			return err
		}
		if _, ok := m[prefix]; ok && ErrOnCollision {
			return errors.New("collision found on key: " + prefix)
		}
		m[prefix] = s
		return nil
	default:
		if _, ok := m[prefix]; ok && ErrOnCollision {
			return errors.New("collision found on key: " + prefix)
		}
		m[prefix] = fmt.Sprintf("%v", v)
		return nil
	}
	return nil
}

func toEnvVariablesFromTomlFile(tomlFile string) (map[string]string, error) {
	f, err := os.Open(tomlFile)
	if err != nil {
		return nil, fmt.Errorf("failed to open toml file: %w", err)
	}
	defer f.Close()

	var out interface{}
	err = toml.NewDecoder(bufio.NewReader(f)).Decode(&out)
	if err != nil {
		return nil, fmt.Errorf("failed to decode toml file: %w", err)
	}

	return toEnvVariables(out)
}

func mergeStringMaps(maps ...map[string]string) map[string]string {
	r := make(map[string]string)
	for _, m := range maps {
		for k, v := range m {
			r[k] = v
		}
	}
	return r
}

func printStringMap(m map[string]string, w io.Writer) error {
	for _, k := range getSortedKeys(m) {
		v := m[k]
		if _, err := fmt.Fprintf(w, "%s=%s\n", k, v); err != nil {
			return err
		}
	}
	return nil
}

func main() {
	if len(os.Args) < 2 {
		_, _ = fmt.Fprintf(os.Stderr, "usage: %s [toml file] [extra files...]\n", os.Args[0])
		os.Exit(1)
	}

	tomlFiles := os.Args[1:]
	varsList := make([]map[string]string, 0, len(tomlFiles))
	for _, tomlFile := range tomlFiles {
		vars, err := toEnvVariablesFromTomlFile(tomlFile)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "error: %s\n", err.Error())
			os.Exit(1)
		}
		varsList = append(varsList, vars)
	}

	vars := mergeStringMaps(varsList...)
	if err := printStringMap(vars, os.Stdout); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "error: %s\n", err.Error())
		os.Exit(1)
	}
}
