%% init

if 1

clear all; close all; clc
globals();
featureDL_folder = '../feature-deeplearning';
feature_BoF_folder = '../feature-BoF';
feature_GIST_folder = '../feature-gist';
feature_GLCM_folder = '../feature-texture';
[annotations_train, annotations_val, annotations_test] = loadAnnotations();
load(fullfile(devkit_folder, 'classes.mat')); % load classes

%% Load Data
Xtrain = []; Xval = []; Xtest = [];
ytrain = []; yval = [];

% load train
fprintf('loading Xtrain...');
for i=1:40,
    filename = sprintf('%s/train_%d.mat', featureDL_folder, i);
    load(filename);
    Xtrain = [Xtrain; scores];
end
fprintf('done\n');
fprintf('loading ytrain...');
for i=1:size(annotations_train,1)
     clss = annotations_train{i}.annotation.classes;
     ytmp = [];
     for j=1:size(classes,2)
        ytmp(1,end+1) = str2double(clss.(classes{j}));
     end
     ytrain(end+1,:) = ytmp;
end
fprintf('done\n');

% load validation
fprintf('loading Xval...');
for i=1:10,
    filename = sprintf('%s/val_%d.mat', featureDL_folder, i);
    load(filename);
    Xval = [Xval; scores];
end
fprintf('done\n');
fprintf('loading yval...');
for i=1:size(annotations_val,1)
     clss = annotations_val{i}.annotation.classes;
     ytmp = [];
     for j=1:size(classes,2)
        ytmp(1,end+1) = str2double(clss.(classes{j}));
     end
     yval(end+1,:) = ytmp;
end
fprintf('done\n');

% load test
fprintf('loading Xtest...');
for i=1:25,
    filename = sprintf('%s/test_%d.mat', featureDL_folder, i);
    load(filename);
    Xtest = [Xtest; scores];
end
fprintf('done\n');

scale = 0.25;

% load additional train
fprintf('loading additional Xtrain...');
filename = sprintf('%s/SIFT_train.mat', feature_BoF_folder);
%filename = sprintf('%s/GIST_train.mat', feature_GIST_folder);
%filename = sprintf('%s/GLCM_train.mat', feature_GLCM_folder);
tmp = load(filename);
Xtrain = [Xtrain, tmp.SIFT_train*scale];
fprintf('done\n');

% load additional train
fprintf('loading additional Xval...');
filename = sprintf('%s/SIFT_val.mat', feature_BoF_folder);
%filename = sprintf('%s/GIST_val.mat', feature_GIST_folder);
%filename = sprintf('%s/GLCM_val.mat', feature_GLCM_folder);
tmp = load(filename);
Xval = [Xval, tmp.SIFT_val*scale];
fprintf('done\n');

% load additional train
fprintf('loading additional Xtest...');
filename = sprintf('%s/SIFT_test.mat', feature_BoF_folder);
%filename = sprintf('%s/GIST_test.mat', feature_GIST_folder);
%filename = sprintf('%s/GLCM_test.mat', feature_GLCM_folder);
tmp = load(filename);
Xtest = [Xtest, tmp.SIFT_test*scale];
fprintf('done\n');




% load additional features (bbox)
fprintf('loading bndbox features...');
filename = '../feature-bndbox.mat';
tmp = load(filename);
Xtrain = [Xtrain, tmp.box_feature_train];
Xval = [Xval, tmp.box_feature_val];
Xtest = [Xtest, tmp.box_feature_test];
fprintf('done\n');



%% DEBUG : shrink the image size
if(flag_debug)
    Xtrain = Xtrain(1:debug_num_imgs, :);
    ytrain = ytrain(1:debug_num_imgs, :);
    Xval   = Xval(1:debug_num_imgs, :);
    yval   = yval(1:debug_num_imgs, :);
    Xtest  = Xtest(1:debug_num_imgs, :);
end

%% Polynomialize
%Xtrain = [Xtrain, Xtrain.^2];
%Xval = [Xval, Xval.^2];
%Xtest = [Xtest, Xtest.^2];

%% Normalize or Whitening
if 0
    % normalize
    if 0
        [Xtrain, mu, sigma] = featureNormalize(Xtrain);
        Xval = featureNormalize(Xval, mu, sigma);
        Xtest = featureNormalize(Xtest, mu, sigma);
    elseif 1
        % train
        min_val = min(Xtrain);
        max_val = max(Xtrain);
        Xtrain = bsxfun(@minus, Xtrain, min_val);
        Xtrain = bsxfun(@rdivide, Xtrain, (max_val - min_val));

        Xval = bsxfun(@minus, Xval, min_val);
        Xval = bsxfun(@rdivide, Xval, (max_val - min_val));

        Xtest = bsxfun(@minus, Xtest, min_val);
        Xtest = bsxfun(@rdivide, Xtest, (max_val - min_val));
    end
elseif 0
    % whitening
    % get statistics of Xtrain
    sigma = cov(Xtrain);
    mu = mean(Xtrain);
    sigma_inv_half = sigma ^ (-0.5);

    % train
    Xtrain = sigma_inv_half * (Xtrain' - repmat(mu', [1 size(Xtrain,1)]));
    Xtrain = Xtrain';

    % val
    Xval = sigma_inv_half * (Xval' - repmat(mu', [1 size(Xval,1)]));
    Xval = Xval';

    % test
    Xtest = sigma_inv_half * (Xtest' - repmat(mu', [1 size(Xtest,1)]));
    Xtest = Xtest';
else
    % No normalization
end


end



%% Train SVM
%svm_c_cand = [1.8:0.06:2.2];
%svm_c_cand = [4 5 6];
%svm_c_cand = [0.1:0.1:0.7];
svm_c_cand = 1;% for submission
svm_type = 0; % 0: linear-kernel, 1:RBF-kernel

result_AP = zeros(length(classes), length(svm_c_cand));

for iii = 1:length(svm_c_cand)
    svm_c = svm_c_cand(iii);
    fprintf('----- svm_c = %d -----\n', svm_c);
    % train
    for i = 1:length(classes)
        % modify training data so that liblinear and libSVM can correctly work
        idx = find(ytrain(:,i)==1);
        X = Xtrain;
        X(1,:) = Xtrain(idx(1),:);
        X(idx(1),:) = Xtrain(1,:);
        Y = ytrain(:,i);
        Y(1) = ytrain(idx(1),i);
        Y(idx(1)) = ytrain(1,i);

        if svm_type == 0
            %opt = sprintf('-s 2 -B 1 -c %f -q', svm_c);
            opt = svm_options{i};
            models{i} = train(Y, sparse(double(X)), opt);
            models{i}.type = 'linear-SVM';
        elseif svm_type == 1
            opt = sprintf('-s 0 -t 2 -c %f -q', svm_c);
            models{i} = svmtrain(Y, sparse(double(X)), opt);
            models{i}.type = 'RBF-SVM';
        end
    end
    
    if 0
        % compute AP
        accuracies = zeros(size(classes,2),1);
        for i = 1:length(classes)
            if svm_type == 0
               [~, ~, prob] = predict(ytrain(:,i), sparse(double(Xtrain)), model{i}, '-q');
            elseif svm_type == 1
                [~, ~, prob] = svmpredict(ytrain(:,i), sparse(double(Xtrain)), model{i}, '-q');
            end
            AP = computeAP(prob, ytrain(:,i), 1)*100;
            accuracies(i, 1) = AP;
            fprintf('Train Accuracy (%13s) : %0.3f%%\n', classes{i}, AP);
        end;
        fprintf('Train Accuracy Average : %0.3f%%\n', mean(accuracies));
    end
    
    
    %% Validate
    % compute AP
    accuracies = zeros(size(classes,2),1);
    for i = 1:length(classes)
        if svm_type == 0
            [~, ~, prob] = predict(yval(:,i), sparse(double(Xval)), models{i}, '-q');
        elseif svm_type == 1
            [~, ~, prob] = svmpredict(yval(:,i), sparse(double(Xval)), models{i}, '-q');
        end
        AP = computeAP(prob, yval(:,i), 1)*100;
        accuracies(i, 1) = AP;
        fprintf('Val Accuracy (%13s) : %0.3f%%\n', classes{i}, AP);
        result_AP(i,iii) = AP;
    end;
    fprintf('Val Accuracy Average : %0.3f%%\n', mean(accuracies));
    
end

%% Show the best svm_c
[v,I] = max(result_AP,[],2);
for i = 1:length(classes)
    fprintf('Best SVM_C (%13s) : %.3f (%.3f%%)\n', classes{i}, svm_c_cand(I(i)), v(i));
end
fprintf('Val Accuracy Average : %0.3f%%\n', mean(v));

%% ReTrain SVM with the best parameters
for i = 1:length(classes)
    % modify training data so that liblinear and libSVM can correctly work
    idx = find(ytrain(:,i)==1);
    X = Xtrain;
    X(1,:) = Xtrain(idx(1),:);
    X(idx(1),:) = Xtrain(1,:);
    Y = ytrain(:,i);
    Y(1) = ytrain(idx(1),i);
    Y(idx(1)) = ytrain(1,i);
    
    if svm_type == 0
        opt = sprintf('-s 2 -B 1 -c %f -q', svm_c_cand(I(i)));
        models{i} = train(Y, sparse(double(X)), opt);
        models{i}.type = 'linear-SVM';
    elseif svm_type == 1
        opt = sprintf('-s 0 -t 2 -c %f -q', svm_c_cand(I(i)));
        models{i} = svmtrain(Y, sparse(double(X)), opt);
        models{i}.type = 'RBF-SVM';
    end
    models{i}.AP = v(i);
    save(fullfile(cache_folder, 'models_SVM.mat'), 'models');
end


%% Predict Test-set
% predict
probs = [];
for i =1:length(classes)
    if svm_type == 0
        [~, ~, prob] = predict(zeros(size(Xtest,1),1), sparse(double(Xtest)), models{i}, '-q');
    elseif svm_type == 1
        [~, ~, prob] = svmpredict(zeros(size(Xtest,1),1), sparse(double(Xtest)), models{i}, '-q');
    end
    probs(end+1,:) = prob;
end
serialize(probs', 'test');
