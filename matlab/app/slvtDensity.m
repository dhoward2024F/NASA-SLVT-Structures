function rho = slvtDensity(altitudeFt, atmosphere)
%SLVTDENSITY Standard atmosphere density in slug/ft^3, altitude in ft ASL.
% Built-in 1976 standard lower atmosphere: troposphere and 11-20 km layer.
% Uses geopotential altitude. Valid geometric input range: -1500 to 65000 ft.
    if nargin < 2, atmosphere = 'standard'; end
    if strcmp(atmosphere, 'external')
        rho = atmos(altitudeFt, 'units', 'US');
        assert(all(isfinite(rho(:))) && all(rho(:) > 0), 'SLVT:Atmosphere', ...
            'atmos.m returned invalid density.');
        return;
    end
    assert(all(isfinite(altitudeFt(:))) && all(altitudeFt(:) >= -1500) && ...
        all(altitudeFt(:) <= 65000), 'SLVT:Atmosphere', ...
        'Built-in atmosphere is valid from -1500 to 65000 ft ASL.');
    z = altitudeFt * 0.3048;
    h = 6356766 .* z ./ (6356766 + z);
    T0 = 288.15; P0 = 101325; R = 287.05287; g0 = 9.80665; L = 0.0065;
    T = T0 - L .* min(h, 11000);
    P = P0 .* (T ./ T0).^(g0 / (R * L));
    upper = h > 11000;
    P(upper) = P(upper) .* exp(-g0 .* (h(upper) - 11000) ./ (R .* T(upper)));
    rho = P ./ (R .* T) * (0.3048^3 / 14.59390294);
end
