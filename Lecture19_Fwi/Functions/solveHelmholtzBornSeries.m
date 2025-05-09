function wvfield = solveHelmholtzBornSeries(x, y, vel, src, f, a0, L_PML, adjoint)
    
% Discretization and Data Dimensions
signConvention = -1; % -1 for exp(-ikr), +1 for exp(+ikr)
dx = single(mean(diff(x))); dy = single(mean(diff(y)));
Nx = numel(x); Ny = numel(y); % Grid Points in X and Y
Nsrcs = size(src,3);

% Whether to Solve Adjoint Helmholtz Equation
if adjoint
    adjointSign = -1; % Change sign if adjoint
else
    adjointSign = 1; % Keep sign same if not adjoint
end
    
% Calculate Complex Wavenumber
k = 2*pi*f./vel; % Wavenumber [1/m]

% Fourier grid - 2*pi*k actually
kx = 2*pi*(mod((0:Nx-1)/(dx*Nx)+1/(2*dx),1/dx)-1/(2*dx));
ky = 2*pi*(mod((0:Ny-1)/(dy*Ny)+1/(2*dy),1/dy)-1/(2*dy)); ky = ky';

% Definition of PML based on Born series paper
N = 9; % polynomial order
c = a0/L_PML; % attenuation [Np/m] inside PML
k0 = sqrt(mean(k.^2,'all')); % mean wavenumber [1/m]
f_boundary_curve = @(r) ...
    (c^2)*(N-c*r+2i*k0*r*signConvention*adjointSign).*((c*r).^(N-1)) ./ ...
    (factorial(N)*polyval(1./factorial(N:-1:0),c*r));
% Apply PML to obtain modified wavenumber map
x_pml = subplus(abs(x)+L_PML-(Nx-1)*dx/2);
y_pml = subplus(abs(y)+L_PML-(Ny-1)*dy/2)';
k = sqrt(k.^2 + f_boundary_curve(sqrt(x_pml.^2+y_pml.^2))); 

% Construct potential map V: 
%   [ V(r) = k(r).^2 - k_0.^2 - i*epsilon ]
% where epsilon must satisfy:
%   [ epsilon >= max(|k(r).^2 - k_0.^2|)  ]
k_0 = (min(real(k(:)))+max(real(k(:))))/2; % medium wavenumber 
V = k.^2-k_0.^2; % Scattering Potential
epsilon = max(abs(V(:)))*signConvention*adjointSign;
V = V-1i*epsilon; % Full potential map V
gamm = 1i/epsilon*V; % Preconditioner gamma

% How many iterations needed for propagate over domain
%   [ pseudo-propagation length per iteration = 2*k_0/epsilon ]
pseudoproplen = 2*k_0/abs(epsilon); % pseudo-propagation length
max_distance = sqrt((Ny*dy)^2+(Nx*dx)^2); % max distance over grid
max_iterations = ceil(max_distance/pseudoproplen); 
fprintf('Maximum iterations = %d\n', max_iterations);

% Calculate Greens function (in Fourier domain/k-space)
%   [ g_0(p) = 1/(|p|.^2 - k_0^2 - i*epsilon) ]
p2 = kx.^2 + ky.^2; % k-space [|p|.^2]
g0_k = 1./(p2-(k_0^2 + 1i*epsilon)); % This one can be precalculated
G = @(csrc) ifft2(g0_k .* fft2(csrc)); % Green's function operator

% Allocate memory 
if canUseGPU
    wvfield = zeros(Ny,Nx,Nsrcs,'single','gpuArray'); % Final Solution
else
    wvfield = zeros(Ny,Nx,Nsrcs,'single'); % Final Solution
end

% Start simulation loop
updateBornSeries = @(wvf) wvf-gamm.*(wvf-G(V.*wvf-src)); % Born-Series Update
for it = 1:max_iterations
    % Convergent Born Series Solution 
    wvfield = updateBornSeries(wvfield); % Update wavefield
end

end