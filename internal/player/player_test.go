package player

import "testing"

func TestClamp(t *testing.T) {
	tests := []struct {
		value int
		want  int
	}{
		{value: -5, want: 0},
		{value: 0, want: 0},
		{value: 70, want: 70},
		{value: 100, want: 100},
		{value: 105, want: 100},
	}
	for _, test := range tests {
		if got := clamp(test.value, 0, 100); got != test.want {
			t.Fatalf("clamp(%d) = %d, want %d", test.value, got, test.want)
		}
	}
}
