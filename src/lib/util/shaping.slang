public module remapping;

public vector<float, N> linstep<uint N>(
    vector<float, N> min,
    vector<float, N> max,
    vector<float, N> x,
) {
    return saturate((x - min) / (max - min));
}