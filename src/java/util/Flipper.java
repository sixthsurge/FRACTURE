package util;

public class Flipper<T> {
	private T first;
	private T second;
	private boolean flipped;

	public Flipper(T first, T second) {
		this.first = first;
		this.second = second;
	}

	public T front() { return this.flipped ? first : second; }

	public T back() { return this.flipped ? second : first; }

	public void flip() { this.flipped = !this.flipped; }
}
