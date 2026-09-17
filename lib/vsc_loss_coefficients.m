function [C, dC_dP, model] = vsc_loss_coefficients(vsc, Pconv, mpc)
% VSC_LOSS_COEFFICIENTS Quadratic loss coefficient by INTERNAL power direction.
% Without mpc.vsc_loss, use each row's legacy LOSS_C for both directions.
% Optional scalar struct mpc.vsc_loss fields (scalar or one per VSC row):
%   c_positive    C for Pconv > 0 (internal injection towards AC), MW/pu-I^2
%   c_negative    C for Pconv < 0 (internal absorption from AC), MW/pu-I^2
%   transition_MW half-width of optional cubic blend; default 0 (hard switch)
% At exactly Pconv=0, a hard switch uses the mean of the two coefficients.
% For Qconv~=0 and unequal C, the hard model is discontinuous at Pconv=0.
% Use an explicitly chosen positive transition_MW for continuous reversal
% studies. dC_dP is per MW, including the blend derivative when enabled.
% At the hard-switch discontinuity dC_dP=0 is only a branch derivative.
% Physical inverter/rectifier names are deliberately avoided: archived
% MatACDC 1.0 calclossac.m labels the positive/negative branches oppositely
% to the physical meaning of its documented AC injection sign convention.
if nargin < 3, mpc = struct; end
c = idx_vsc;
n = size(vsc,1);
Pconv = Pconv(:);
if ~isnumeric(Pconv) || ~isreal(Pconv) || numel(Pconv) ~= n || any(~isfinite(Pconv))
    error('vsc_loss_coefficients:power', 'Pconv must contain one finite real MW value per VSC row.');
end
fallback = vsc(:,c.LOSS_C);
model = struct('c_positive',fallback,'c_negative',fallback,'transition_MW',zeros(n,1));
if isfield(mpc,'vsc_loss') && ~isempty(mpc.vsc_loss)
    data = mpc.vsc_loss;
    if ~isstruct(data) || ~isscalar(data) || ...
            ~isfield(data,'c_positive') || ~isfield(data,'c_negative')
        error('vsc_loss_coefficients:metadata', ...
            'mpc.vsc_loss requires c_positive and c_negative in a scalar struct.');
    end
    names = fieldnames(data);
    if any(~ismember(names,fieldnames(model)))
        error('vsc_loss_coefficients:metadata','Unknown mpc.vsc_loss field.');
    end
    for j=1:numel(names)
        name = names{j};
        val = data.(name);
        if ~isnumeric(val) || ~isreal(val) || isempty(val) || ...
                ~(isscalar(val) || (isvector(val) && numel(val)==n)) || ...
                any(~isfinite(val(:))) || any(val(:)<0)
            error('vsc_loss_coefficients:metadata', ...
                '%s must be a finite non-negative scalar or vector of length %d.',name,n);
        end
        if isscalar(val), val = repmat(val,n,1); end
        model.(name) = val(:);
    end
end
Cp = model.c_positive;
Cn = model.c_negative;
w = model.transition_MW;
C = Cn;
C(Pconv>0) = Cp(Pconv>0);
zero = Pconv==0;
C(zero) = (Cp(zero)+Cn(zero))/2;
dC_dP = zeros(n,1);
blend = w>0 & abs(Pconv)<w;
% Cubic smoothstep is C1 at both band edges and exact outside the band.
t = (Pconv(blend)./w(blend)+1)/2;
h = t.^2.*(3-2*t);
C(blend) = Cn(blend)+(Cp(blend)-Cn(blend)).*h;
dC_dP(blend) = (Cp(blend)-Cn(blend)).*3.*t.*(1-t)./w(blend);
end
