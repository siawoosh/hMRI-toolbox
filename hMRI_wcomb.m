function hMRI_wcomb(PIn1,PIn2,Pw1,Pw2,PVG,PMSK)
% This function combines two input images (PIn1 and PIn2) using two weight 
% images (Pw1 and Pw2) for each input image, respectively. PVG is used as
% reference (space defining image). If PVG is unspecified, it will
% automatically use PIn1.
% S. Mohammadi 18/10/2019
% In:
% PIn           - Filepath & name of two input images
% Pw            - Filepath & name of two weight images
% 
% Out:
% 

wcombparams = hmri_get_defaults('wcombparams');
res         = wcombparams.res;
kt          = wcombparams.kt;
dummy_am    = wcombparams.dummy_am;
smthk       = wcombparams.smthk;
dim         = wcombparams.dim;
dummy_error = wcombparams.dummy_error;


dt = [spm_type('float32'),spm_platform('bigend')]; % for nifti output


% read in data
switch dim
    case 1
       dplane = [2 3];
    case 2
       dplane = [1 3];
    case 3
       dplane = [1 2];
end
VIn1 = spm_vol(PIn1);
VIn2 = spm_vol(PIn2);
Vw1 = spm_vol(Pw1);
Vw2 = spm_vol(Pw2);
% define reference volume
if exist('PVG','var') && ~isempty(PVG)
    VG = spm_vol(PVG);
else
    VG = spm_vol(VIn1(1));    
end

if exist('PMSK','var') && ~isempty(PMSK)
    VMSK = spm_vol(PMSK);
    AMSK = hMRI_read_vols(VMSK,VG,res,[],dim);
else
    AMSK = ones(VG.dim);
end

for inx = 1:size(VIn1,1)
    % define output volume
    Pout = spm_file(VIn1(inx).fname,'prefix','wa_');
    
    Ntmp = hMRI_create_nifti(Pout,VG,dt,deblank([VIn1(inx).descrip  ' - weighted combination']));
    if dummy_error==true
        Pout = spm_file(Vw1(inx).fname,'prefix','wa_');
        Ntmperror = hMRI_create_nifti(Pout,VG,dt,deblank([VIn1(inx).descrip  ' - weighted combination error maps']));
    end
    if dummy_am==true
        Pout = spm_file(VIn1(inx).fname,'prefix','am_');
        Ntmpam = hMRI_create_nifti(Pout,VG,dt,deblank([VIn1(inx).descrip  ' - arithmetic combination']));
    end
    spm_progress_bar('Init',VG.dim(3),Ntmp.descrip,'planes completed');

    if smthk>0
        %     % smooth weights
        vxg         = sqrt(sum(VG.mat(1:3,1:3).^2));
        smthk       = smthk.*vxg;
        Aw1 = hMRI_read_vols(Vw1(inx),VG,res,[],dim);
        Aw2 = hMRI_read_vols(Vw2(inx),VG,res,[],dim);
        sAw1 = Aw1;
        sAw2 = Aw2;
        spm_smooth (sAw1,Aw1, smthk);
        spm_smooth (sAw2,Aw2, smthk);
    end    
    for p = 1:VG.dim(dim)
        AIn1 = hMRI_read_vols(VIn1(inx),VG,res,p,dim);
        AIn2 = hMRI_read_vols(VIn2(inx),VG,res,p,dim);
        if dummy_am==true
            Aam = (AIn1 + AIn2)./2;
            read_nifti_perm(Ntmpam,reshape(Aam(:),VG.dim(dplane)),dim,p)    
        end
        if smthk>0
            Aw1 = sAw1(:,:,p);
            Aw2 = sAw2(:,:,p);
        else
            Aw1 = hMRI_read_vols(Vw1(inx),VG,res,p,dim);
            Aw2 = hMRI_read_vols(Vw2(inx),VG,res,p,dim);
        end
        if false
            if p==1
                f1on = figure;
            end
            if numel(find(AMSK(:,:,p)>0))<1e1
                f1 = 1;
                f2 = 1;
            else

                nAw1 = Aw1(AMSK(:,:,p)>0)./Aw2(AMSK(:,:,p)>0);
                nAw1(nAw1<0)=1;
                f1 = local_fermi(nAw1,kt,f1on,'k.'); % we take 1- to down-weigh regions that have high res
            end
            hold off;
            if (p==85) && (inx==3)
                disp('stop')
            end
            drawnow
            
            if p==VG.dim(dim)
                close(f1on)
            end
        else
            if numel(find(AMSK(:,:,p)>0))<1e1
                f1 = 1;
                f2 = 1;
            else
                nAw1 = Aw1(AMSK(:,:,p)>0)./Aw2(AMSK(:,:,p)>0);
                nAw1(nAw1<0)=1;
                f1 = local_fermi(nAw1,kt); % we take 1- to down-weigh regions that have high res           
            end
        end

        Awavg = zeros(VG.dim(dplane));
        if ~isempty(find(AMSK(:,:,p)>0))
            Awavg(AMSK(:,:,p)>0) = (AIn1(AMSK(:,:,p)>0).*f1 + AIn2(AMSK(:,:,p)>0).*(max(f1)-f1))./max(f1);
        end
        read_nifti_perm(Ntmp,reshape(Awavg,VG.dim(dplane)),dim,p)

        Awerr = zeros(VG.dim(dplane));
        if dummy_error
            Awerr(AMSK(:,:,p)>0) = (Aw1(AMSK(:,:,p)>0).*f1 + Aw2(AMSK(:,:,p)>0).*(max(f1)-f1))./max(f1);
        end
        read_nifti_perm(Ntmperror,reshape(Awerr,VG.dim(dplane)),dim,p)
        
        spm_progress_bar('Set',p);
    end
    spm_progress_bar('Clear');
end

end

function f= local_fermi(x,kt,f1,symb)
% This is a fermi function that goes from 1 to 0 at the point 1. kt provides the steepness 
% with which the transition is done.
% S.Mohammadi 2.10.2019
    f = 1./(exp((x-1)/kt)+1);

    if exist('f1','var')
        plot(x,f,symb);
        xlim([0 5]);
        set(gca,'fontsize', 20);
        hold on;
    end
    
end

function read_nifti_perm(Nif,A,dim,p)
% This function reads the data A into the nifti file Nif, accounting for
% the permutation of dimension defined by dim.
% S.Mohammadi 18.10.2019
    switch dim
        case 1
            Aout(1,:,:) = A; 
            Nif.dat(p,:,:) = Aout;
        case 2
            Aout(:,1,:) = A; 
            Nif.dat(:,p,:) = Aout;
        case 3
            Nif.dat(:,:,p) = A;
    end        
end